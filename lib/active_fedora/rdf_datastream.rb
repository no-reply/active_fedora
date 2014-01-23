module ActiveFedora
  class RDFDatastream < ActiveFedora::Datastream
    include Solrizer::Common
    extend Rdf::RdfProperties

    delegate :rdf_subject, :set_value, :get_values, :to => :resource

    before_save do
      if content.blank?
        logger.warn "Cowardly refusing to save a datastream with empty content: #{self.inspect}"
        false
      end
    end

    def metadata?
      true
    end

    def content
      serialize
    end

    def content=(content)
      resource.clear!
      resource << RDF::Reader.for(serialization_format).new(content)
      content
    end

    def content_changed?
      return false unless instance_variable_defined? :@resource
      @content = serialize
      super
    end

    # Utility method which can be overridden to determine the object
    # resource that is created.
    def resource_class
      Rdf::ObjectResource
    end

    ##
    # The resource is the RdfResource object that stores the graph for
    # the datastream and is the central point for its relationship to
    # other nodes.
    #
    # set_value, get_value, and property accessors are delegated to this object.
    def resource
      @resource ||= begin
                      r = resource_class.new(digital_object ? pid : nil)
                      r.singleton_class.properties = self.class.properties
                      r << RDF::Reader.for(serialization_format).new(datastream_content) if datastream_content
                      r
                    end
    end

    alias_method :graph, :resource


    ##
    # This method allows for delegation.
    # This patches the fact that there's no consistent API for allowing delegation - we're matching the
    # OMDatastream implementation as our "consistency" point.
    # @TODO: We may need to enable deep RDF delegation at one point.
    def term_values(*values)
      self.send(values.first)
    end

    def update_indexed_attributes(hash)
      hash.each do |fields, value|
        fields.each do |field|
          self.send("#{field}=", value)
        end
      end
    end

    def serialize
      resource.set_subject!(pid) if digital_object and pid and rdf_subject.node?
      resource.dump serialization_format
    end

    def deserialize(data=nil)
      return RDF::Graph.new if new? && data.nil?
      data ||= datastream_content
      data.force_encoding('utf-8')
      RDF::Graph.new << RDF::Reader.for(serialization_format).new(data)
    end

    def serialization_format
      raise "you must override the `serialization_format' method in a subclass"
    end

    def to_solr(solr_doc = Hash.new) # :nodoc:
      fields.each do |field_key, field_info|
        values = resource.get_values(field_key)
        if values
          Array.wrap(values).each do |val|
            val = val.to_s if val.kind_of? RDF::URI
            val = val.solrize if val.kind_of? Rdf::RdfResource
            self.class.create_and_insert_terms(prefix(field_key), val, field_info[:behaviors], solr_doc)
          end
        end
      end
      solr_doc
    end

    def prefix(name)
      name = name.to_s unless name.is_a? String
      pre = dsid.underscore
      return "#{pre}__#{name}".to_sym
    end

    private

    ##
    # Builds a map of properties with values, type and index behaviors
    # for consumption by to_solr.
    def fields
      field_map = {}.with_indifferent_access

      self.class.properties.each do |name, config|
        type = config[:type]
        behaviors = config[:behaviors]
        next unless type and behaviors
        next if config[:class_name] && config[:class_name] < ActiveFedora::Base
        resource.query(:subject => rdf_subject, :predicate => config[:predicate]).each_statement do |statement|
          field_map[name] ||= {:values => [], :type => type, :behaviors => behaviors}
          field_map[name][:values] << statement.object.to_s
        end
      end
      return field_map
    end

  end
end

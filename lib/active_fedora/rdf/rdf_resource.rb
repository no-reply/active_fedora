module ActiveFedora::Rdf
  ##
  # Defines a generic RdfResource as an RDF::Graph with property
  # configuration, accessors, and some other methods for managing
  # "resources" as discrete subgraphs which can be managed by a Hydra
  # datastream model.
  #
  # Resources can be instances of RdfResource directly, but more
  # often they will be instances of subclasses with registered
  # properties and configuration. e.g.
  #
  #    class License < RdfResource
  #      configure :repository => :default
  #      property :title, :predicate => RDF::DC.title, :class_name => RDF::Literal do |index|
  #        index.as :displayable, :facetable
  #      end
  #    end
  class RdfResource < RDF::Graph
    @@type_registry
    extend RdfConfigurable
    extend RdfProperties
    include ActiveFedora::Rdf::NestedAttributes
    attr_accessor :parent, :datastream

    def self.type_registry
      @@type_registry ||= {}
    end

    ##
    # Adapter for a consistent interface for creating a new node from a URI.
    # Similar functionality should exist in all objects which can become a node.
    def self.from_uri(uri,vals=nil)
      new(uri, vals)
    end

    ##
    # Initialize an instance of this resource class. Defaults to a
    # blank node subject. In addition to RDF::Graph parameters, you
    # can pass in a URI and/or a parent to build a resource from a
    # existing data.
    #
    # You can pass in only a parent with:
    #    RdfResource.new(nil, parent)
    #
    # @see RDF::Graph
    def initialize(*args, &block)
      resource_uri = args.shift unless args.first.is_a?(Hash)
      self.parent = args.shift unless args.first.is_a?(Hash)
      set_subject!(resource_uri) if resource_uri
      super(*args, &block)
      reload
      # Append type to graph if necessary.
      self.get_values(:type) << self.class.type if self.class.type.kind_of?(RDF::URI) && type.empty?
    end

    def final_parent
      @final_parent ||= begin
        parent = self.parent
        while parent && parent.parent && parent.parent != parent
          parent = parent.parent
        end
        parent
      end
    end

    def attributes=(values)
      raise ArgumentError, "values must be a Hash, you provided #{values.class}" unless values.kind_of? Hash
      values.with_indifferent_access.each do |key, value|
        if self.class.properties.keys.include?(key)
          set_value(rdf_subject, key, value)
        elsif nested_attributes_options.keys.map{ |k| "#{k}_attributes"}.include?(key)
          send("#{key}=".to_sym, value)
        end
      end
    end

    def rdf_subject
      @rdf_subject ||= RDF::Node.new
    end

    def node?
      return true if rdf_subject.kind_of? RDF::Node
      false
    end

    def base_uri
      self.class.base_uri
    end

    def type
      return self.get_values(:type).to_a.map{|x| x.rdf_subject}
    end

    def type=(type)
      raise "Type must be an RDF::URI" unless type.kind_of? RDF::URI
      self.update(RDF::Statement.new(rdf_subject, RDF.type, type))
    end

    ##
    # Look for labels in various default fields, prioritizing
    # configured label fields
    def rdf_label
      labels = Array.wrap(self.class.rdf_label)
      labels += default_labels
      labels.each do |label|
        values = get_values(label)
        return values unless values.empty?
      end
      return node? ? [] : [rdf_subject.to_s]
    end

    def fields
      properties.keys.map(&:to_sym).reject{|x| x == :type}
    end

    ##
    # Load data from URI
    # @TODO: use graph name context for provenance
    def fetch
      load(rdf_subject)
      self
    end

    def persist!
      raise "failed when trying to persist to non-existant repository or parent resource" unless repository
      each_statement do |s,p,o|
        repository.delete [s, p, nil]
      end
      if node?
        repository.statements.each do |statement|
          repository.send(:delete_statement, statement) if statement.subject == rdf_subject
        end
      end
      repository << self
      @persisted = true
    end

    def persisted?
      @persisted ||= false
    end

    ##
    # Repopulates the graph from the repository or parent resource.
    def reload
      @term_cache ||= {}
      if self.class.repository == :parent
        return false if final_parent.nil?
      end
      self << repository.query(:subject => rdf_subject)
      unless empty?
        @persisted = true
      end
      true
    end

    ##
    # Adds or updates a property with supplied values.
    #
    # Handles two argument patterns. The recommended pattern is:
    #    set_value(property, values)
    #
    # For backwards compatibility, there is support for explicitly
    # passing the rdf_subject to be used in the statement:
    #    set_value(uri, property, values)
    #
    # @note This method will delete existing statements with the correct subject and predicate from the graph
    def set_value(*args)
      # Add support for legacy 3-parameter syntax
      if args.length > 3 || args.length < 2
        raise ArgumentError("wrong number of arguments (#{args.length} for 2-3)")
      end
      values = args.pop
      get_term(args).set(values)
    end

    ##
    # Returns an array of values belonging to the property
    # requested. Elements in the array may RdfResource objects or a
    # valid datatype.
    #
    # Handles two argument patterns. The recommended pattern is:
    #    get_values(property)
    #
    # For backwards compatibility, there is support for explicitly
    # passing the rdf_subject to be used in th statement:
    #    get_values(uri, property)
    def get_values(*args)
      get_term(args)
    end

    def get_term(args)
      @term_cache ||= {}
      term = ActiveFedora::Rdf::Term.new(self, args)
      @term_cache["#{term.rdf_subject}/#{term.property}"] ||= term
      @term_cache["#{term.rdf_subject}/#{term.property}"]
    end

    ##
    # Set a new rdf_subject for the resource.
    #
    # This raises an error if the current subject is not a blank node,
    # and returns false if it can't figure out how to make a URI from
    # the param. Otherwise it creates a URI for the resource and
    # rebuilds the graph with the updated URI.
    #
    # Will try to build a uri as an extension of the class's base_uri
    # if appropriate.
    #
    # @param [#to_uri, #to_s] uri_or_str the uri or string to use
    def set_subject!(uri_or_str)
      raise "Refusing update URI when one is already assigned!" unless node?
      # Refusing set uri to an empty string.
      return false if uri_or_str.nil? or uri_or_str.to_s.empty?
      # raise "Refusing update URI! This object is persisted to a datastream." if persisted?
      old_subject = rdf_subject
      if uri_or_str.respond_to? :to_uri
        @rdf_subject = uri_or_str.to_uri
      elsif uri_or_str.to_s.start_with? '_:'
        if uri_or_str.kind_of?(RDF::Node)
          @rdf_subject = uri_or_str
        else
          @rdf_subject = RDF::Node(uri_or_str.to_s[2..-1])
        end
      elsif uri_or_str.to_s.start_with? 'http://' or uri_or_str.to_s.start_with? 'info:fedora/'
        @rdf_subject = RDF::URI(uri_or_str.to_s)
      elsif base_uri && !uri_or_str.to_s.start_with?(base_uri.to_s)
        separator = self.base_uri.to_s[-1,1] =~ /(\/|#)/ ? '' : '/'
        @rdf_subject = RDF::URI.intern(self.base_uri.to_s + separator + uri_or_str.to_s)
      elsif
        @rdf_subject = RDF::URI(uri_or_str)
      end

      unless empty?
        each_statement do |statement|
          if statement.subject == old_subject
            delete(statement)
            self << RDF::Statement.new(rdf_subject, statement.predicate, statement.object)
          elsif statement.object == old_subject
            delete(statement)
            self << RDF::Statement.new(statement.subject, statement.predicate, rdf_subject)
          end
        end
      end
    end

    def destroy
      clear
      persist!
      parent.destroy_child(self)
    end

    def destroy_child(child)
      statements.each do |statement|
        delete_statement(statement) if statement.subject == child.rdf_subject || statement.object == child.rdf_subject
      end
    end

    def new_record?
      if parent
        return parent.new_record?
      end
      return true
    end

    ##
    # @return [String] the string to index in solr
    #
    # @TODO: is there a better pattern for bnodes than indexing the rdf_label?
    def solrize
      node? ? rdf_label : rdf_subject.to_s
    end

    def mark_for_destruction
      @marked_for_destruction = true
    end

    def marked_for_destruction?
      @marked_for_destruction
    end

    private

    def properties
      self.singleton_class.properties
    end

    def property_for_predicate(predicate)
      properties.each do |property, values|
        return property if values[:predicate] == predicate
      end
      return nil
    end

    def default_labels
      [RDF::SKOS.prefLabel,
       RDF::DC.title,
       RDF::RDFS.label,
       RDF::SKOS.altLabel,
       RDF::SKOS.hiddenLabel]
    end

    ##
    # Return the repository (or parent) that this resource should
    # write to when persisting.
    def repository
      @repository ||= begin
        if self.class.repository == :parent
          final_parent
        else
          ActiveFedora::Rdf::RdfRepositories.repositories[self.class.repository]
        end
      end
    end

  end
end

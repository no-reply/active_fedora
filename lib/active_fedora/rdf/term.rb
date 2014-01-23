module ActiveFedora::Rdf
  class Term
    attr_accessor :parent, :value_arguments
    delegate *(Array.public_instance_methods - [:__send__, :__id__, :class, :object_id] + [:as_json]), :to => :result
    def initialize(parent, value_arguments)
      self.parent = parent
      self.value_arguments = value_arguments
    end

    def clear
      set(nil)
      # Delete all the assertions about this object
      #parent.delete([rdf_subject, nil, nil])
    end

    def result
      result = node_result if parent.node?
      result ||= standard_result
      return result if !property_config || property_config[:multivalue]
      result.first
    end

    def set(values)
      values = Array.wrap(values)
      parent.delete([rdf_subject, predicate, nil])
      values.each do |val|
        val = RDF::Literal(val) if val.kind_of? String
        val = val.resource if val.respond_to?(:resource)
        if val.kind_of? RdfResource
          add_child_node(val)
          next
        end
        val = val.to_uri if val.respond_to? :to_uri
        raise 'value must be an RDF URI, Node, Literal, or a plain string' unless
            val.kind_of? RDF::Value or val.kind_of? RDF::Literal
        parent.insert [rdf_subject, predicate, val]
      end
    end

    private

    def add_child_node(resource)
      parent.insert [rdf_subject, predicate, resource.rdf_subject]
      resource.parent = parent
      resource.persist! if resource.class.repository == :parent
    end

    def property_config
      parent.send(:properties)[property]
    end

    def standard_result
      values = []
      parent.query(:subject => rdf_subject, :predicate => predicate).each_statement do |statement|
        value = statement.object
        value = value.to_s if value.kind_of? RDF::Literal
        value = parent.send(:make_node,property, value) if value.kind_of? RDF::Value
        values << value unless value.nil?
      end
      return values
    end

    def node_result
      values = []
      parent.each_statement do |statement|
        value = statement.object if statement.subject == rdf_subject && statement.predicate == predicate
        value = value.to_s if value.kind_of? RDF::Literal
        value = parent.send(:make_node,property, value) if value.kind_of? RDF::Value
        values << value unless value.nil?
      end
      return values
    end

    def predicate
      parent.send(:predicate_for_property,property)
    end

    def property
      value_arguments.last
    end

    def rdf_subject
      raise ArgumentError("wrong number of arguments (#{value_arguments.length} for 1-2)") if value_arguments.length < 1 || value_arguments.length > 2
      if value_arguments.length > 1
        return value_arguments.first
      else
        return parent.rdf_subject
      end
    end

  end
end
module ActiveFedora::Rdf
  class Term
    attr_accessor :parent, :value_arguments, :node_cache
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

    def build(attributes={})
      new_subject = attributes.key?('id') ? attributes.delete('id') : RDF::Node.new
      node = make_node(new_subject)
      node.attributes = attributes
      self.push node
    end

    def delete(*values)
      values.each do |value|
        parent.delete([rdf_subject, predicate, value])
      end
    end

    def << (values)
      values = Array.wrap(result) | Array.wrap(values)
          self.set(values)
    end

    alias_method :push, :<<

    def property_config
      parent.send(:properties)[property]
    end

    def reset!
    end

    private

    def node_cache
      @node_cache ||= {}
    end

    def add_child_node(resource)
      parent.insert [rdf_subject, predicate, resource.rdf_subject]
      resource.parent = parent
      resource.persist! if resource.class.repository == :parent
    end

    def standard_result
      values = []
      parent.query(:subject => rdf_subject, :predicate => predicate).each_statement do |statement|
        value = statement.object
        value = value.to_s if value.kind_of? RDF::Literal
        value = make_node(value) if value.kind_of? RDF::Value
        values << value unless value.nil?
      end
      return values
    end

    def node_result
      values = []
      parent.each_statement do |statement|
        value = statement.object if statement.subject == rdf_subject && statement.predicate == predicate
        value = value.to_s if value.kind_of? RDF::Literal
        value = make_node(value) if value.kind_of? RDF::Value
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

    ##
    # Build a child resource or return it from this object's cache
    #
    # Builds the resource from the class_name specified for the
    # property.
    def make_node(value)
      klass = class_for_property
      value = RDF::Node.new if value.nil?
      return node_cache[value] if node_cache[value]
      node = klass.from_uri(value,parent)
      node_cache[value] = node
      return node
    end

    def final_parent
      @final_parent ||= begin
        parent = self.parent
        while parent != parent.parent && parent.parent
          parent = parent.parent
        end
        if parent.datastream
          return parent.datastream
        end
        parent
      end
    end

    def class_for_property
      klass = property_config[:class_name]
      klass ||= ActiveFedora::Rdf::RdfResource
      klass = ActiveFedora.class_from_string(klass, final_parent.class) if klass.kind_of? String
      klass
    end

  end
end
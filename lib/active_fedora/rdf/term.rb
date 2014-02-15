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
      result ||= standard_result
      result = result.reject(&:nil?)
      return result if !property_config || property_config[:multivalue]
      result.first
    end

    def set(values)
      values = Array.wrap(values)
      parent.query([rdf_subject, predicate, nil]).each_statement do |statement|
        if !uri_class(statement.object) || uri_class(statement.object) == class_for_property
          parent.delete(statement)
        end
      end
      values.each do |val|
        val = RDF::Literal(val) if valid_datatype? val
        val = val.resource if val.respond_to?(:resource)
        if val.kind_of? Resource
          node_cache[val.rdf_subject] = nil
          add_child_node(val)
          next
        end
        val = val.to_uri if val.respond_to? :to_uri
        raise 'value must be an RDF URI, Node, Literal, or a valid datatype. See RDF::Literal' unless
            val.kind_of? RDF::Value or val.kind_of? RDF::Literal
        parent.insert [rdf_subject, predicate, val]
      end
      parent.persist! if parent.class.repository == :parent && parent.send(:repository)
    end

    def build(attributes={})
      new_subject = attributes.key?('id') ? attributes.delete('id') : RDF::Node.new
      node = make_node(new_subject)
      node.attributes = attributes
      self.push node
      node
    end

    def first_or_create(attributes={})
      result.first || build(attributes)
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
      return type_property if (property == RDF.type || property.to_s == "type") && !parent.send(:properties)[property]
      parent.send(:properties)[property]
    end

    def type_property
      {:multivalue => true, :predicate => RDF.type}
    end

    def reset!
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

   # protected

    def node_cache
      @node_cache ||= {}
    end

    def add_child_node(resource)
      parent.insert [rdf_subject, predicate, resource.rdf_subject]
      resource.parent = parent
      self.node_cache[resource.rdf_subject] = resource
      resource.persist! if resource.class.repository == :parent
    end

    def standard_result
      values = []
      parent.query(:subject => rdf_subject, :predicate => predicate).each_statement do |statement|
        value = statement.object
        value = value.object if value.kind_of? RDF::Literal
        value = make_node(value) if value.kind_of? RDF::Resource
        values << value unless value.nil?
      end
      return values
    end

    def predicate
      return property_config[:predicate] unless property.kind_of? RDF::URI
      return property
    end

    def valid_datatype?(val)
      val.is_a? String or val.is_a? Date or val.is_a? Time or val.is_a? Numeric or val.is_a? Symbol or val == !!val
    end

    ##
    # Build a child resource or return it from this object's cache
    #
    # Builds the resource from the class_name specified for the
    # property.
    def make_node(value)
      klass = class_for_value(value)
      value = RDF::Node.new if value.nil?
      node = node_cache[value] if node_cache[value]
      node ||= klass.from_uri(value,parent)
      return nil if property_config[:class_name] && class_for_value(value) != class_for_property
      self.node_cache[value] ||= node
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

    def class_for_value(v)
      uri_class(v) || class_for_property
    end

    def uri_class(v)
      v = RDF::URI.new(v) if v.kind_of? String
      type_uri = parent.query([v, RDF.type, nil]).to_a.first.try(:object)
      return ActiveFedora::Rdf::Resource.type_registry[type_uri]
    end

    def class_for_property
      klass = property_config[:class_name]
      klass ||= ActiveFedora::Rdf::Resource
      klass = ActiveFedora.class_from_string(klass, final_parent.class) if klass.kind_of? String
      klass
    end

  end
end
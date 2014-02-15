module ActiveFedora::Rdf
  class RdfList < RDF::List
    include ActiveFedora::Rdf::NestedAttributes
    extend RdfProperties

    delegate :rdf_subject, :set_value, :get_values, :attributes=, :to => :resource    
    
    def initialize(*args)
      super
      @graph = ListResource.new(subject) << graph
    end

    def resource
      graph
    end

    def []=(idx, value)
      raise IndexError if idx < 0 or idx > length
      return self << value if idx == length
      each_subject.with_index do |v, i|
        puts v
        graph.update RDF::Statement(v, RDF.first, value) if i == idx
      end
    end

    def self.from_uri(uri, vals=nil)
      list = ListResource.from_uri(uri, vals)
      self.new(list.rdf_subject, list)
    end

    class ListResource < RdfResource
    end

    ##
    # Monkey patch to allow lists to have subject URIs.
    # Overrides shift in RDF::List to prevent URI subjects
    # from being replaced with nodes.
    #
    # @NOTE Lists built this way will return false for #valid?
    def <<(value)
      value = case value
              when nil         then RDF.nil
              when RDF::Value  then value
              when Array       then RDF::List.new(nil, graph, value)
              else value
              end

      if empty?
        @subject = RDF::Node.new if @subject == RDF.nil
        new_subject = subject
      else
        old_subject, new_subject = last_subject, RDF::Node.new
        graph.delete([old_subject, RDF.rest, RDF.nil])
        graph.insert([old_subject, RDF.rest, new_subject])
      end

      graph.insert([new_subject, RDF.first, value.is_a?(RDF::List) ? value.subject : value])
      graph.insert([new_subject, RDF.rest, RDF.nil])

      self
    end
  end
end

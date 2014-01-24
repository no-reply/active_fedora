# This is a VERY temporary workaround to enable basic lists. Awaiting @tjohnson for something better.
module ActiveFedora::Rdf::RdfList
  extend ActiveSupport::Concern
  included do
    def [](index)
      self.send(self.class.list)[index]
    end
  end
  module ClassMethods
    def list
      @list
    end
    def list=(value)
      @list = value
    end
  end
end
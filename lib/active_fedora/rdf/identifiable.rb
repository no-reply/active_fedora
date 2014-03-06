##
# This module is included to allow for an ActiveFedora::Base object to be set as the class_name for a Resource.
# Enables functionality like:
#   base = ActiveFedora::Base.new('oregondigital:1')
#   base.title = 'test'
#   base.save
#   subject.descMetadata.set = base
#   subject.descMetadata.set # => <ActiveFedora::Base>
#   subject.descMetadata.set.title # => 'test'
module ActiveFedora::Rdf::Identifiable
  extend ActiveSupport::Concern
  delegate :parent, :dump, :query, :rdf_type, :to => :resource
  ##
  # Defines which resource defines this ActiveFedora object.
  # This is required for ActiveFedora::Rdf::Resource#set_value to append graphs.
  # @TODO: Consider allowing multiple defining metadata streams.
  def resource
    self.send(self.class.resource_datastream).resource
  end
  module ClassMethods
    def resource_datastream
      self.ds_specs.each do |dsid, conf|
        return dsid.to_sym if conf[:type].respond_to? :rdf_subject
      end
      return :descMetadata
    end
    ##
    # Finds the appropriate ActiveFedora::Base object given a URI from a graph.
    # Expected by the API in ActiveFedora::Rdf::Resource
    # @TODO: Generalize this.
    # @see ActiveFedora::Rdf::Resource.from_uri
    # @param [RDF::URI] uri URI that is being looked up.
    def from_uri(uri,_)
      return self.find(pid_from_subject(uri))
    end
    ##
    # Finds the pid of an object from its RDF subject, override this
    # for URI configurations not of form base_uri + pid
    # @param [RDF::URI] uri URI to convert to pid
    def pid_from_subject(uri)
      return uri.to_s.gsub(self.ds_specs[resource_datastream.to_s][:type].resource_class.base_uri,"")
    end
  end

end

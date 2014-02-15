module ActiveFedora::Rdf
  ##
  # A class of RdfResources to act as the primary/root resource associated
  # with a Datastream and ActiveFedora::Base object.
  #
  # @see OregonDigital::RdfResourceDatastream
  class ObjectResource < Resource
    configure :base_uri => 'info:fedora/'
  end
end

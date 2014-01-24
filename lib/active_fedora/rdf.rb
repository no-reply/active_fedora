module ActiveFedora
  module Rdf
    extend ActiveSupport::Autoload
    autoload :NestedAttributes
    autoload :NodeConfig
    autoload :Indexing
    autoload :RdfConfigurable
    autoload :RdfProperties
    autoload :RdfIdentifiable
    autoload :RdfRepositories
    autoload :RdfResource
    autoload :VocabularyLoader
    autoload :ObjectResource
    autoload :Term
    autoload :RdfList
  end
end

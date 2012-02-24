# coding: UTF-8

# This class knows nothing about Rails.root or Rails.application.routes,
# and therefore is easier to test without a Rails app.
class RailsTranslateRoutes
  TRANSLATABLE_SEGMENT = /^([\w-]+)(\()?/.freeze
  LOCALE_PARAM_KEY = :locale.freeze
  ROUTE_HELPER_CONTAINER = [
    ActionController::Base,
    ActionView::Base,
    ActionMailer::Base,
    ActionDispatch::Routing::UrlFor
  ].freeze

  # Attributes

  attr_accessor :dictionary

  def available_locales
    @available_locales ||= I18n.available_locales.map(&:to_s)
  end

  def available_locales= locales
    @available_locales = locales.map(&:to_s)
  end

  def default_locale
    @default_locale ||= I18n.default_locale.to_s
  end

  def default_locale= locale
    @default_locale = locale.to_s
  end

  def default_locale? locale
    default_locale == locale.to_s
  end

  def prefix_on_default_locale
    @prefix_on_default_locale ||= I18n.default_locale.to_s
  end

  def prefix_on_default_locale= locale
    @prefix_on_default_locale = locale.to_s
  end

  def no_prefixes
    @no_prefixes ||= false
  end

  def no_prefixes= no_prefixes
    @no_prefixes = no_prefixes
  end

  class << self
    # Default locale suffix generator
    def locale_suffix locale
      locale.to_s.underscore
    end

    # Creates a RailsTranslateRoutes instance, using I18n dictionaries of
    # your app
    def init_with_i18n *wanted_locales
      new.tap do |t|
        t.init_i18n_dictionary *wanted_locales
      end
    end

    # Creates a RailsTranslateRoutes instance and evaluates given block
    # with an empty dictionary
    def init_with_yield &block
      new.tap do |t|
        t.yield_dictionary &block
      end
    end

    # Creates a RailsTranslateRoutes instance and reads the translations
    # from a specified file
    def init_from_file file_path
      new.tap do |t|
        t.load_dictionary_from_file file_path
      end
    end
  end

  module DictionaryManagement
    # Resets dictionary and yields the block wich can be used to manually fill the dictionary
    # with translations e.g.
    #   route_translator = RailsTranslateRoutes.new
    #   route_translator.yield_dictionary do |dict|
    #     dict['en'] = { 'people' => 'people' }
    #     dict['de'] = { 'people' => 'personen' }
    #   end
    def yield_dictionary &block
      reset_dictionary
      yield @dictionary
      set_available_locales_from_dictionary
    end

    # Resets dictionary and loads translations from specified file
    # config/locales/routes.yml:
    #   en:
    #     people: people
    #   de:
    #     people: personen
    # routes.rb:
    #   ... your routes ...
    #   ActionDispatch::Routing::Translator.translate_from_file
    # or, to specify a custom file
    #   ActionDispatch::Routing::Translator.translate_from_file 'config', 'locales', 'routes.yml'
    def load_dictionary_from_file file_path
      reset_dictionary
      add_dictionary_from_file file_path
    end

    # Add translations from another file to the dictionary.
    def add_dictionary_from_file file_path
      yaml = YAML.load_file(file_path)
      yaml.each_pair do |locale, translations|
        merge_translations locale, translations
      end
      set_available_locales_from_dictionary
    end

    # Merge translations for a specified locale into the dictionary
    def merge_translations locale, translations
      locale = locale.to_s
      if translations.blank?
        @dictionary[locale] ||= {}
        return
      end
      @dictionary[locale] = (@dictionary[locale] || {}).merge(translations)
    end

    # Init dictionary to use I18n to translate route parts. Creates
    # a hash with a block for each locale to lookup keys in I18n dynamically.
    def init_i18n_dictionary *wanted_locales
      wanted_locales = available_locales if wanted_locales.blank?
      reset_dictionary
      wanted_locales.each do |locale|
        @dictionary[locale] = Hash.new do |hsh, key|
          hsh[key] = I18n.translate key, :locale => locale #DISCUSS: caching or no caching (store key and translation in dictionary?)
        end
      end
      @available_locales = @dictionary.keys.map &:to_s
    end

    private
    def set_available_locales_from_dictionary
      @available_locales = @dictionary.keys.map &:to_s
    end

    # Resets dictionary
    def reset_dictionary
      @dictionary = { default_locale => {}}
    end
  end
  include DictionaryManagement

  module Translator
    # Translate a specific RouteSet, usually Rails.application.routes, but can
    # be a RouteSet of a gem, plugin/engine etc.
    def translate route_set
      Rails.logger.info "Translating routes (default locale: #{default_locale})" if defined?(Rails) && defined?(Rails.logger)

      # save original routes and clear route set
      original_routes = route_set.routes.dup                     # Array [routeA, routeB, ...]

      if Rails.version >= '3.2'
        original_routes.routes.delete_if{|r| r.path.spec.to_s == '/assets'  }
      else
        original_routes.delete_if{|r| r.path == '/assets'}
      end

      original_named_routes = route_set.named_routes.routes.dup  # Hash {:name => :route}

      if Rails.version >= '3.2'
        translated_routes = []
        original_routes.each do |original_route|
          translations_for(original_route).each do |translated_route_args|
            translated_routes << translated_route_args
          end
        end

        reset_route_set route_set

        translated_routes.each do |translated_route_args|
          route_set.add_route *translated_route_args
        end
      else
        reset_route_set route_set

        original_routes.each do |original_route|
          translations_for(original_route).each do |translated_route_args|
            route_set.add_route *translated_route_args
          end
        end
      end

      original_named_routes.each_key do |route_name|
        route_set.named_routes.helpers.concat add_untranslated_helpers_to_controllers_and_views(route_name)
      end

      if root_route = original_named_routes[:root]
        add_root_route root_route, route_set
      end

    end

    # Add unmodified root route to route_set
    def add_root_route root_route, route_set
      if @prefix_on_default_locale
        if Rails.version >= '3.2'
          conditions = { :path_info => root_route.path.spec.to_s }
          conditions[:request_method] = parse_request_methods root_route.verb if root_route.verb != //
          route_set.add_route root_route.app, conditions, root_route.requirements, root_route.defaults, root_route.name
        else
          root_route.conditions[:path_info] = root_route.conditions[:path_info].dup
          route_set.set.add_route *root_route
          route_set.named_routes[root_route.name] = root_route
          route_set.routes << root_route
        end
      end
    end

    # Add standard route helpers for default locale e.g.
    #   I18n.locale = :de
    #   people_path -> people_de_path
    #   I18n.locale = :fr
    #   people_path -> people_fr_path
    def add_untranslated_helpers_to_controllers_and_views old_name
      ['path', 'url'].map do |suffix|
        new_helper_name = "#{old_name}_#{suffix}"

        ROUTE_HELPER_CONTAINER.each do |helper_container|
          helper_container.send :define_method, new_helper_name do |*args|
            send "#{old_name}_#{locale_suffix(I18n.locale)}_#{suffix}", *args
          end
        end

        new_helper_name.to_sym
      end
    end

    # Generate translations for a single route for all available locales
    def translations_for route
      available_locales.map do |locale|
        translate_route route, locale
      end
    end

    # Generate translation for a single route for one locale
    def translate_route route, locale
      if Rails.version >= '3.2'
        conditions = { :path_info => translate_path(route.path.spec.to_s, locale) }
        conditions[:request_method] = parse_request_methods route.verb if route.verb != //
        conditions[:subdomain] = route.constraints[:subdomain] if route.constraints
        defaults = route.defaults.merge LOCALE_PARAM_KEY => locale.dup
      else
        conditions = { :path_info => translate_path(route.path, locale) }
        conditions[:request_method] = parse_request_methods route.conditions[:request_method] if route.conditions.has_key? :request_method
        defaults = route.defaults.merge LOCALE_PARAM_KEY => locale
      end

      requirements = route.requirements.merge LOCALE_PARAM_KEY => locale
      new_name = "#{route.name}_#{locale_suffix(locale)}" if route.name

      [route.app, conditions, requirements, defaults, new_name]
    end

    # Add prefix for all non-default locales
    def add_prefix? locale
      if @no_prefixes
        false
      elsif !default_locale?(locale) || @prefix_on_default_locale
        true
      else
        false
      end
    end

    # Translates a path and adds the locale prefix.
    def translate_path path, locale
      final_optional_segments = path.match(/(\(.+\))$/)[1] rescue nil   # i.e: (.:format)
      path_without_optional_segments = final_optional_segments ? path.gsub(final_optional_segments,'') : path
      path_segments = path_without_optional_segments.split("/")
      new_path = path_segments.map{ |seg| translate_path_segment(seg, locale) }.join('/')
      new_path = "/#{locale.downcase}#{new_path}" if add_prefix?(locale)
      new_path = '/' if new_path.blank?
      final_optional_segments ? new_path + final_optional_segments : new_path
    end

    # Tries to translate a single path segment. If the path segment
    # contains sth. like an optional format "people(.:format)", only
    # "people" will be translated, if there is no translation, the path
    # segment is blank or begins with a ":" (param key), the segment
    # is returned untouched
    def translate_path_segment segment, locale
      return segment if segment.blank? or segment.starts_with?(":")

      match = TRANSLATABLE_SEGMENT.match(segment)[1] rescue nil

      (translate_string(match, locale) || segment)
    end

    def translate_string str, locale
      @dictionary[locale.to_s][str.to_s]
    end

    private
    def reset_route_set route_set
      route_set.clear!
      remove_all_methods_in route_set.named_routes.module
    end

    def remove_all_methods_in mod
      mod.instance_methods.each do |method|
        mod.send :remove_method, method
      end
    end

    # expects methods regexp to be in a format: /^GET$/ or /^GET|POST$/ and returns array ["GET", "POST"]
    def parse_request_methods methods_regexp
      methods_regexp.source.gsub(/\^([a-zA-Z\|]+)\$/, "\\1").split("|")
    end
  end
  include Translator

  def locale_suffix locale
    self.class.locale_suffix locale
  end
end

# Adapter for Rails 3 apps
module ActionDispatch
  module Routing
    module Translator
      class << self
        def translate &block
          RailsTranslateRoutes.init_with_yield(&block).translate Rails.application.routes
        end

        def translate_from_file(file_path, options = {})
          file_path = %w(config locales routes.yml) if file_path.blank?
          r = RailsTranslateRoutes.init_from_file(File.join(Rails.root, file_path))
          r.prefix_on_default_locale = true if options && options[:prefix_on_default_locale] == true
          r.no_prefixes = true if options && options[:no_prefixes] == true
          r.translate Rails.application.routes
        end

        def i18n *locales
          RailsTranslateRoutes.init_with_i18n(*locales).translate Rails.application.routes
        end
      end
    end
  end
end

# Add set_locale_from_url to controllers
ActionController::Base.class_eval do
  private
  # called by before_filter
  def set_locale_from_url
    I18n.locale = params[RailsTranslateRoutes::LOCALE_PARAM_KEY]
    default_url_options = {RailsTranslateRoutes::LOCALE_PARAM_KEY => I18n.locale}
  end
end

# Add locale_suffix to controllers, views and mailers
RailsTranslateRoutes::ROUTE_HELPER_CONTAINER.each do |klass|
  klass.class_eval do
    private
    def locale_suffix locale
      RailsTranslateRoutes.locale_suffix locale
    end
  end
end

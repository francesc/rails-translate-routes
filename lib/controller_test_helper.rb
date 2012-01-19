# This monkey patch injects the locale in the controller's params 
# Reason: ActionController::TestCase doesn't support "default_url_options"
#
# Example: when the request you are testing needs the locale, e.g.
#   get :show, :id => 1, :locale => 'en'
#
# if the monkey patch was loaded, you can just do:
#   get :show, :id => 1

class ActionController::TestCase

  module Behavior
    def process_with_default_locale(action, parameters = nil, session = nil, flash = nil, http_method = 'GET')
      parameters = { :locale => I18n.default_locale }.merge(parameters || {} )
      process_without_default_locale(action, parameters, session, flash, http_method)
    end
    alias_method_chain :process, :default_locale
  end
end

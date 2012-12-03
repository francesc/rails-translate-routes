# rails-translate-routes

**Important change from version 0.0.5 (Feb 2012) to 0.1.0 (June 2012)**: if you're updating from an earlier version take into account that now translations defined in routes.yml are namespaced to avoid conflicts with other translations from app (thanks to cawel for the patch). To upgrade you just have to add the namespace `routes` to your `routes.yml (see example in the below docs).

Rails >=3.1 routes translations based on Raul's translate_routes (https://github.com/raul/translate_routes).

It's currently a stripped down version of the forked gem, adding some bugfixes for rails 3.1 and features I needed for my project. See doc below to see what it can do.

translate_routes & i18n_routes seems to be unmaintained projects so I decided to start a fork of the first one for my own projects, I can't promise high dedication but I'll try to maintain it for my own use and take care all patches & bugs submitted, help is welcome!

## Installation

Add it to your Gemfile:

    gem 'rails-translate-routes'

## Basic usage

Let's imagine you have a SampleApp with products and a contact page. A typical `routes.rb` file should look like:

    SampleApp::Application.routes.draw do
      resources :products
      match 'contact', :to => 'pages#contact'
    end

Running `rake routes we have:

        products GET    /products(.:format)          {:action=>"index", :controller=>"products"}
                 POST   /products(.:format)          {:action=>"create", :controller=>"products"}
     new_product GET    /products/new(.:format)      {:action=>"new", :controller=>"products"}
    edit_product GET    /products/:id/edit(.:format) {:action=>"edit", :controller=>"products"}
         product GET    /products/:id(.:format)      {:action=>"show", :controller=>"products"}
                 PUT    /products/:id(.:format)      {:action=>"update", :controller=>"products"}
                 DELETE /products/:id(.:format)      {:action=>"destroy", :controller=>"products"}
         contact        /contact(.:format)           {:action=>"contact", :controller=>"pages"}

We want to have them in two languages english and spanish, to accomplish this with rails-translate-routes:

1) We have to activate the translations appending this line to the end of `routes.rb

    ActionDispatch::Routing::Translator.translate_from_file('config/locales/routes.yml')

2) Now we can write translations on a standard YAML file (e.g: in `config/locales/routes.yml`), including all the locales and their translations:

    en:
      routes:
        # you can leave empty locales, for example the default one
    es:
      routes:
        products: productos
        contact: contacto
        new: crear

3) Include this filter in your `ApplicationController:

    before_filter :set_locale_from_url

Also remember to include language detection to your app, a simple example of an `ApplicationController

    class ApplicationController < ActionController::Base
      protect_from_forgery

      before_filter :set_locale
      before_filter :set_locale_from_url

      private

      def set_locale
        I18n.locale = params[:locale] || ((lang = request.env['HTTP_ACCEPT_LANGUAGE']) && lang[/^[a-z]{2}/])
      end
    end

And that's it! Now if we execute `rake routes`

        products_en GET    /products(.:format)              {:action=>"index", :controller=>"products"}
        products_es GET    /es/productos(.:format)          {:action=>"index", :controller=>"products"}
                    POST   /products(.:format)              {:action=>"create", :controller=>"products"}
                    POST   /es/productos(.:format)          {:action=>"create", :controller=>"products"}
     new_product_en GET    /products/new(.:format)          {:action=>"new", :controller=>"products"}
     new_product_es GET    /es/productos/new(.:format)      {:action=>"new", :controller=>"products"}
    edit_product_en GET    /products/:id/edit(.:format)     {:action=>"edit", :controller=>"products"}
    edit_product_es GET    /es/productos/:id/edit(.:format) {:action=>"edit", :controller=>"products"}
         product_en GET    /products/:id(.:format)          {:action=>"show", :controller=>"products"}
         product_es GET    /es/productos/:id(.:format)      {:action=>"show", :controller=>"products"}
                    PUT    /products/:id(.:format)          {:action=>"update", :controller=>"products"}
                    PUT    /es/productos/:id(.:format)      {:action=>"update", :controller=>"products"}
                    DELETE /products/:id(.:format)          {:action=>"destroy", :controller=>"products"}
                    DELETE /es/productos/:id(.:format)      {:action=>"destroy", :controller=>"products"}
         contact_en        /contact(.:format)               {:action=>"contact", :controller=>"pages"}
         contact_es        /es/contacto(.:format)           {:action=>"contact", :controller=>"pages"}
            root_en        /                                {:controller=>"public", :action=>"index"}
            root_es        /es                              {:controller=>"public", :action=>"index"}

The application recognizes the different routes and sets the `I18n.locale` value in controllers, but what about the routes generation? As you can see on the previous rake routes execution, the `contact_es_path` and `contact_en_path` routing helpers have been generated and are available in your controllers and views. Additionally, a `contact_path` helper has been generated, which generates the routes according to the current request's locale. This means that if you use named routes you don't need to modify your application links because the routing helpers are automatically adapted to the current locale.

## URL structure options

### Default URL structure

By default it generates the following url structure:

    /
    /es
    /products/
    /es/productos/
    /contact/
    /es/contacto/


### All languages prefixed

In case you want the default languages to be scoped resulting in the following structure:

    /en
    /es
    /en/products/
    /es/productos/
    /en/contact/
    /es/contacto/

You can specify the following option:

    ActionDispatch::Routing::Translator.translate_from_file('config/locales/routes.yml', { :prefix_on_default_locale => true })

If you use the `prefix_on_default_locale` you will have to make the proper redirect on your root controller from http://www.sampleapp.com/ to http://www.sampleapp.com/en or http://www.sampleapp.com/es rails-translate-routes adds an extra unstranslated root path:

    root_en        /en                              {:controller=>"pages", :action=>"index"}
    root_es        /es                              {:controller=>"pages", :action=>"index"}
       root        /                                {:controller=>"pages", :action=>"index"}

A simple example of a redirection to user locale in index method:

    def index
      unless params[ :locale]
        # it takes I18n.locale from the previous example set_locale as before_filter in application controller
        redirect_to eval("root_#{I18n.locale}_path")
      end

      # rest of the controller logic ...
    end

### No prefixed languages

In case you don't want the language prefix in the url path because you have a domain or subdomain per language (or any other reason). Resulting in this structure:

    /
    /products/
    /productos/
    /contact/
    /contacto/

You can specify the following option:

    ActionDispatch::Routing::Translator.translate_from_file('config/locales/routes.yml', { :no_prefixes => true })

Note that the `no_prefixes` option will override the `prefix_on_default_locale` option.

### Keep untranslated routes

In case you want to keep access to untranslated routes, for easier api or ajax integration for example. Resulting in this structure:

    /en/available-products
    /fr/produits-disponibles/
    /products/

You can specify the following option:

    ActionDispatch::Routing::Translator.translate_from_file('config/locales/routes.yml', { :keep_untranslated_routes => true })

This option is not meant to be used with `no_prefixes`.

### Namespaced backends

I usually build app backend in namespaced controllers, routes, ... using translated routes will result in duplicated routes or prefixed ones. In most cases you won't want to have the backend in several languages, you can set `routes.rb` this way:

    SampleApp::Application.routes.draw do
      resources :products
      match 'contact', :to => 'pages#contact'
    end

    ActionDispatch::Routing::Translator.translate_from_file('config/locales/routes.yml', { :prefix_on_default_locale => true })

    SampleApp::Application.routes.draw do
      namespace :admin do
        resources :products
        root :to => "admin_products#index"
      end
    end

## Translation YAML options

By default translations of routes are specified on a single YAML file (e.g: in `config/locales/routes.yml`), but in some cases you might want to split the routes translations on several files. For example having all application translations files a in folder per language:

    # config/locales/en
    rails_defaults.yml
    application.yml
    routes.yml

    # config/locales/es
    rails_defaults.yml
    application.yml
    routes.yml

To pass several YAML files to rails-translate-routes you can pass an array of paths:

    ActionDispatch::Routing::Translator.translate_from_file(I18n.available_locales.map { |locale| "config/locales/#{locale}/routes.yml" }, { :prefix_on_default_locale => true })

## Testing

Once your app is locale-aware, the routes are dependent on the locale. This means that in functional tests, you need to explicitly include the locale like so:

    get :show, :id => 1, :locale => 'en'

But in case you would prefer the locale to be implicit or simply because you don't want to add the locale param to all your previous functional tests, you can require the `lib/controller_test_helper` file (typically from your test helper file) and then this will work fine:

    get :show, :id => 1

## TODO

Help is welcome ;)

* make basic testing

## Credits

Thanks to:

Contributors of the current gem:
  * Martin Carel (https://github.com/cawel)
  * Johan Gyllenspetz (https://github.com/gyllen)
  * Nico Ritsche (https://github.com/ncri)
  * Jean-Loup Fenaux (https://github.com/jlfenaux)
  * Cyril Mouge (https://github.com/shingara)
  * Nicolas Arbogast (https://github.com/NicoArbogast)
  * Stephan van Eijkelenburg (https://github.com/stephanvane)
  * Víctor Martín (https://github.com/eltercero)

Main development of forked gem:
  * Raul Murciano (http://github.com/raul)

Contributors of forked gem:
  * Aitor Garay-Romero (http://github.com/aitorgr)
  * Christian Hølmer (http://github.com/hoelmer)
  * Nico Ritsche (https://github.com/ncri)
  * Cedric Darricau (http://github.com/devsigner)
  * Olivier Gonzalez (http://github.com/gonzoyumo)
  * Kristian Mandrup (http://github.com/kristianmandrup)
  * Pieter Visser (http://github.com/pietervisser)
  * Marian Theisen (http://github.com/cice)
  * Enric Lluelles (http://github.com/enriclluelles)
  * Jaime Iniesta (http://github.com/jaimeiniesta)

## Similar projects

Another fork of translate_routes, a much cleaner approach with better testing but less flexible than rails-translate-routes:

* route_translator (https://github.com/enriclluelles/route_translator)

Also there are other two projects for translating routes in Rails (which I know of), both of them are unfortunately unmaintained but you may want to check them out if you use old Rails versions or have different needs.

* translate_routes (https://github.com/raul/translate_routes)
* i18n_routing (https://github.com/kwi/i18n_routing)

## Other i18n related projects

If you also need to translate models check out: https://github.com/francesc/rails-translate-models

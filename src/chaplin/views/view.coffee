'use strict'

_ = require 'underscore'
Backbone = require 'backbone'
utils = require 'chaplin/lib/utils'
EventBroker = require 'chaplin/lib/event_broker'

# Shortcut to access the DOM manipulation library
$ = Backbone.$

module.exports = class View extends Backbone.View

  # Mixin an EventBroker
  _(@prototype).extend EventBroker

  # Automatic rendering
  # -------------------

  # Flag whether to render the view automatically on initialization.
  # As an alternative you might pass a `render` option to the constructor.
  autoRender: false

  # Automatic inserting into DOM
  # ----------------------------

  # View container element
  # Set this property in a derived class to specify the container element.
  # Normally this is a selector string but it might also be an element or
  # jQuery object.
  # The view is automatically inserted into the container when it’s rendered.
  # As an alternative you might pass a `container` option to the constructor.
  container: null

  # Method which is used for adding the view to the DOM
  # Like jQuery’s `html`, `prepend`, `append`, `after`, `before` etc.
  containerMethod: 'append'

  # Subviews
  # --------

  # List of subviews
  subviews: null
  subviewsByName: null

  constructor: (options) ->
    # Wrap `initialize` so `afterInitialize` is called afterwards
    # Only wrap if there is an overriding method, otherwise we
    # can call the `after-` method directly
    unless @initialize is View::initialize
      utils.wrapMethod this, 'initialize'

    # Wrap `render` so `afterRender` is called afterwards
    if @render is View::render
      @render = _(@render).bind this
    else
      utils.wrapMethod this, 'render'

    # Copy some options to instance properties
    if options
      _(this).extend _.pick options, [
        'autoRender', 'container', 'containerMethod'
      ]

    # Call Backbone’s constructor
    super

    # Set up declarative bindings after `initialize` has been called
    # so initialize may set model/collection and create or bind methods
    @delegateListeners()

    # Listen for disposal of the model or collection.
    # If the model is disposed, automatically dispose the associated view
    @listenTo @model, 'dispose', @dispose if @model
    @listenTo @collection, 'dispose', @dispose if @collection

  # Inheriting classes must call `super` in their `initialize` method to
  # properly inflate subviews and set up options
  initialize: (options) ->
    # No super call here, Backbone’s `initialize` is a no-op

    # Initialize subviews
    @subviews = []
    @subviewsByName = {}

    # Call `afterInitialize` if `initialize` was not wrapped
    unless @initializeIsWrapped
      @afterInitialize()

  # This method is called after a specific `initialize` of a derived class
  afterInitialize: ->
    # Render automatically if set by options or instance property
    @render() if @autoRender

  # User input event handling
  # -------------------------

  # Event handling using event delegation
  # Register a handler for a specific event type
  # For the whole view:
  #   delegate(eventName, handler)
  #   e.g.
  #   @delegate('click', @clicked)
  # For an element in the passing a selector:
  #   delegate(eventName, selector, handler)
  #   e.g.
  #   @delegate('click', 'button.confirm', @confirm)
  delegate: (eventName, second, third) ->
    if typeof eventName isnt 'string'
      throw new TypeError 'View#delegate: first argument must be a string'

    if arguments.length is 2
      handler = second
    else if arguments.length is 3
      selector = second
      if typeof selector isnt 'string'
        throw new TypeError 'View#delegate: ' +
          'second argument must be a string'
      handler = third
    else
      throw new TypeError 'View#delegate: ' +
        'only two or three arguments are allowed'

    if typeof handler isnt 'function'
      throw new TypeError 'View#delegate: ' +
        'handler argument must be function'

    # Add an event namespace, bind handler it to view.
    list = _.map eventName.split(' '), (event) => "#{event}.delegate#{@cid}"
    events = list.join(' ')
    bound = _.bind handler, this
    @$el.on events, (selector or null), bound

    # Return the bound handler.
    bound

  # Copy of original backbone method without `undelegateEvents` call.
  _delegateEvents: (events) ->
    # Call Backbone.delegateEvents on all superclasses events.
    for key, value of events
      handler = if typeof value is 'function' then value else this[value]
      throw new Error "Method '#{handler}' does not exist" unless handler
      match = key.match /^(\S+)\s*(.*)$/
      eventName = "#{match[1]}.delegateEvents#{@cid}"
      selector = match[2]
      bound = _.bind handler, this
      @$el.on eventName, (selector or null), bound
    return

  # Override Backbones method to combine the events
  # of the parent view if it exists.
  delegateEvents: (events) ->
    @undelegateEvents()
    if events
      @_delegateEvents events
      return
    for classEvents in utils.getAllPropertyVersions this, 'events'
      if typeof classEvents is 'function'
        throw new TypeError 'View#delegateEvents: functions are not supported'
      @_delegateEvents classEvents
    return

  # Remove all handlers registered with @delegate.
  undelegate: ->
    @$el.unbind ".delegate#{@cid}"

  # Handle declarative event bindings from `listen`
  delegateListeners: ->
    return unless @listen

    # Walk all `listen` hashes in the prototype chain
    for version in utils.getAllPropertyVersions this, 'listen'
      for key, method of version
        # Get the method, ensure it is a function
        if typeof method isnt 'function'
          method = this[method]
        if typeof method isnt 'function'
          throw new Error 'View#delegateListeners: ' +
            "#{method} must be function"

        # Split event name and target.
        [eventName, target] = key.split ' '
        @delegateListener eventName, target, method

    return

  delegateListener: (eventName, target, callback) ->
    if target in ['model', 'collection']
      prop = this[target]
      @listenTo prop, eventName, callback if prop
    else if target is 'mediator'
      @subscribeEvent eventName, callback
    else if not target
      @on eventName, callback, this

    return

  # Subviews
  # --------

  # Getting or adding a subview
  subview: (name, view) ->
    if name and view
      # Add the subview, ensure it’s unique
      @removeSubview name
      @subviews.push view
      @subviewsByName[name] = view
      view
    else if name
      # Get and return the subview by the given name
      @subviewsByName[name]

  # Removing a subview
  removeSubview: (nameOrView) ->
    return unless nameOrView

    if typeof nameOrView is 'string'
      # Name given, search for a subview by name
      name = nameOrView
      view = @subviewsByName[name]
    else
      # View instance given, search for the corresponding name
      view = nameOrView
      for otherName, otherView of @subviewsByName
        if view is otherView
          name = otherName
          break

    # Break if no view and name were found
    return unless name and view and view.dispose

    # Dispose the view
    view.dispose()

    # Remove the subview from the lists
    index = _(@subviews).indexOf(view)
    @subviews.splice index, 1 if index > -1
    delete @subviewsByName[name]

  # Rendering
  # ---------

  # Get the model/collection data for the templating function
  # Uses optimized Chaplin serialization if available.
  getTemplateData: ->
    data = if @model
      utils.serialize @model
    else if @collection
      {items: utils.serialize(@collection), length: @collection.length}
    else
      {}

    source = @model or @collection
    if source
      # If the model/collection is a Deferred, add a `resolved` flag,
      # but only if it’s not present yet
      if typeof source.state is 'function' and not ('resolved' of data)
        data.resolved = source.state() is 'resolved'

      # If the model/collection is a SyncMachine, add a `synced` flag,
      # but only if it’s not present yet
      if typeof source.isSynced is 'function' and not ('synced' of data)
        data.synced = source.isSynced()

    data

  # Returns the compiled template function
  getTemplateFunction: ->
    # Chaplin doesn’t define how you load and compile templates in order to
    # render views. The example application uses Handlebars and RequireJS
    # to load and compile templates on the client side. See the derived
    # View class in the example application:
    # https://github.com/chaplinjs/facebook-example/blob/master/coffee/views/base/view.coffee
    #
    # If you precompile templates to JavaScript functions on the server,
    # you might just return a reference to that function.
    # Several precompilers create a global `JST` hash which stores the
    # template functions. You can get the function by the template name:
    # JST[@templateName]

    throw new Error 'View#getTemplateFunction must be overridden'

  # Main render function
  # This method is bound to the instance in the constructor (see above)
  render: ->
    # Do not render if the object was disposed
    # (render might be called as an event handler which wasn’t
    # removed correctly)
    return false if @disposed

    templateFunc = @getTemplateFunction()
    if typeof templateFunc is 'function'

      # Call the template function passing the template data
      html = templateFunc @getTemplateData()

      # Replace HTML
      # ------------

      # This is a workaround for an apparent issue with jQuery 1.7’s
      # innerShiv feature. Using @$el.html(html) caused issues with
      # HTML5-only tags in IE7 and IE8.
      @$el.empty().append html

    # Call `afterRender` if `render` was not wrapped
    @afterRender() unless @renderIsWrapped

    # Return the view
    this

  # This method is called after a specific `render` of a derived class
  afterRender: ->
    # Automatically append to DOM if the container element is set
    if @container
      # Append the view to the DOM
      $(@container)[@containerMethod] @el
      # Trigger an event
      @trigger 'addedToDOM'

  # Disposal
  # --------

  disposed: false

  dispose: ->
    return if @disposed

    throw new Error('Your `initialize` method must include a super call to
      Chaplin `initialize`') unless @subviews?

    # Dispose subviews
    subview.dispose() for subview in @subviews

    # Unbind handlers of global events
    @unsubscribeAllEvents()

    # Unbind all referenced handlers
    @stopListening()

    # Remove all event handlers on this module
    @off()

    # Remove the topmost element from DOM. This also removes all event
    # handlers from the element and all its children.
    @$el.remove()

    # Remove element references, options,
    # model/collection references and subview lists
    properties = [
      'el', '$el',
      'options', 'model', 'collection',
      'subviews', 'subviewsByName',
      '_callbacks'
    ]
    delete this[prop] for prop in properties

    # Finished
    @disposed = true

    # You’re frozen when your heart’s not open
    Object.freeze? this

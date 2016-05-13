do ($Cypress, _) ->

  $Cypress.Cy.extend
    getErrMessage: (errPath, args)->
      errMessage = $Cypress.Utils.getObjValueByPath $Cypress.ErrorMessages, errPath
      throw new Error "Error message path '#{errPath}' does not exist" if not errMessage
      _.reduce args, (message, argValue, argKey)->
        message.replace(new RegExp("\{\{#{argKey}\}\}", "g"), argValue)
      , errMessage

    internalErr: (err)->
      err = new Error(err)
      err.name = "InternalError"
      err

    cypressErr: (err) ->
      $Cypress.Utils.cypressError(err)

    throwUnexpectedErr: (err, options = {})->
      @_handleErr(err, options)

    throwErr: (errPath, options = {}) ->
      err = try
        @getErrMessage errPath, options.args
      catch e
        err = @internalErr e

      @_handleErr(err, options)

    _handleErr: (err, options)->
      if _.isString(err)
        err = @cypressErr(err)

      onFail = options.onFail
      ## assume onFail is a command if
      ## onFail is present and isnt a function
      if onFail and not _.isFunction(onFail)
        command = onFail

        ## redefine onFail and automatically
        ## hook this into our command
        onFail = (err) ->
          command.error(err)

      err.onFail = onFail if onFail

      throw err

    ## submit a generic command error
    commandErr: (err) ->
      current = @prop("current")

      @Cypress.Log.command
        end: true
        snapshot: true
        error: err
        onConsole: ->
          obj = {}
          ## if type isnt parent then we know its dual or child
          ## and we can add Applied To if there is a prev command
          ## and it is a parent
          if current.get("type") isnt "parent" and prev = current.get("prev")
            ret = if $Cypress.Utils.hasElement(prev.get("subject"))
              $Cypress.Utils.getDomElements(prev.get("subject"))
            else
              prev.get("subject")

            obj["Applied To"] = ret
            obj

    checkTestErr: (test) ->
      ## if our test has an error but we dont
      ## have one referenced then set this err
      ## this can happen if there is an window
      ## uncaught error from our test which
      ## bypasses our commands entirely so
      ## we never actually catch it
      ## and 'endedEarlyErr' would fire
      if err = test.err and not @prop("err")
        @prop("err", err)

      return @

    endedEarlyErr: (index) ->
      ## return if we already have an error
      return if @prop("err")

      commands = @commands.slice(index).reduce (memo, cmd) =>
        if @isCommandFromThenable(cmd) or @isCommandFromMocha(cmd)
          memo
        else
          memo.push "- " + cmd.stringify()
          memo
      , []

      err = @cypressErr("""
        Oops, Cypress detected something wrong with your test code.

        The test has finished but Cypress still has commands in its queue.
        The #{commands.length} queued commands that have not yet run are:

        #{commands.join('\n')}

        In every situation we've seen, this has been caused by programmer error.
        Most often this indicates a race condition due to a forgotten 'return' or from commands in a previously run test bleeding into the current test.

        For a much more thorough explanation including examples please review this error here:

        https://on.cypress.io/command-queue-ended-early
      """)
      err.onFail = ->
      @fail(err)

    fail: (err) ->
      ## make sure we cancel our outstanding
      ## promise since we could have hit this
      ## fail handler outside of a command chain
      ## and we want to ensure we don't continue retrying
      @prop("promise")?.cancel()

      current = @prop("current")

      ## allow for our own custom onFail function
      if err.onFail
        err.onFail.call(@, err)

        ## clean up this onFail callback
        ## after its been called
        delete err.onFail
      else
        @commandErr(err)

      runnable = @private("runnable")

      @prop("err", err)

      @Cypress.trigger "fail", err, runnable
      @trigger "fail", err, runnable

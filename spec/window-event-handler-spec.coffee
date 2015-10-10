KeymapManager = require 'atom-keymap'
path = require 'path'
fs = require 'fs-plus'
temp = require 'temp'
TextEditor = require '../src/text-editor'
WindowEventHandler = require '../src/window-event-handler'
ipc = require 'ipc'

describe "WindowEventHandler", ->
  [projectPath, windowEventHandler] = []

  beforeEach ->
    spyOn(atom, 'hide')
    initialPath = atom.project.getPaths()[0]
    spyOn(atom, 'getLoadSettings').andCallFake ->
      loadSettings = atom.getLoadSettings.originalValue.call(atom)
      loadSettings.initialPath = initialPath
      loadSettings
    atom.project.destroy()
    windowEventHandler = new WindowEventHandler(atom)
    projectPath = atom.project.getPaths()[0]

  afterEach ->
    windowEventHandler.unsubscribe()

  describe "when the window is loaded", ->
    it "doesn't have .is-blurred on the body tag", ->
      expect(document.body.className).not.toMatch("is-blurred")

  describe "when the window is blurred", ->
    beforeEach ->
      window.dispatchEvent(new CustomEvent('blur'))

    afterEach ->
      document.body.classList.remove('is-blurred')

    it "adds the .is-blurred class on the body", ->
      expect(document.body.className).toMatch("is-blurred")

    describe "when the window is focused again", ->
      it "removes the .is-blurred class from the body", ->
        window.dispatchEvent(new CustomEvent('focus'))
        expect(document.body.className).not.toMatch("is-blurred")

  describe "window:close event", ->
    it "closes the window", ->
      spyOn(atom, 'close')
      window.dispatchEvent(new CustomEvent('window:close'))
      expect(atom.close).toHaveBeenCalled()

  describe "beforeunload event", ->
    beforeEach ->
      jasmine.unspy(TextEditor.prototype, "shouldPromptToSave")
      spyOn(ipc, 'send')

    describe "when pane items are modified", ->
      editor = null
      beforeEach ->
        waitsForPromise -> atom.workspace.open("sample.js").then (o) -> editor = o
        runs -> editor.insertText("I look different, I feel different.")

      it "prompts the user to save them, and allows the unload to continue if they confirm", ->
        spyOn(atom.workspace, 'confirmClose').andReturn(true)
        window.dispatchEvent(new CustomEvent('beforeunload'))
        expect(atom.workspace.confirmClose).toHaveBeenCalled()
        expect(ipc.send).not.toHaveBeenCalledWith('cancel-window-close')

      it "cancels the unload if the user selects cancel", ->
        spyOn(atom.workspace, 'confirmClose').andReturn(false)
        window.dispatchEvent(new CustomEvent('beforeunload'))
        expect(atom.workspace.confirmClose).toHaveBeenCalled()
        expect(ipc.send).toHaveBeenCalledWith('cancel-window-close')

  describe "when a link is clicked", ->
    it "opens the http/https links in an external application", ->
      shell = require 'shell'
      spyOn(shell, 'openExternal')

      link = document.createElement('a')
      linkChild = document.createElement('span')
      link.appendChild(linkChild)
      link.href = 'http://github.com'
      jasmine.attachToDOM(link)
      fakeEvent = {target: linkChild, currentTarget: link, preventDefault: (->)}

      windowEventHandler.handleLinkClick(fakeEvent)
      expect(shell.openExternal).toHaveBeenCalled()
      expect(shell.openExternal.argsForCall[0][0]).toBe "http://github.com"
      shell.openExternal.reset()

      link.href = 'https://github.com'
      windowEventHandler.handleLinkClick(fakeEvent)
      expect(shell.openExternal).toHaveBeenCalled()
      expect(shell.openExternal.argsForCall[0][0]).toBe "https://github.com"
      shell.openExternal.reset()

      link.href = ''
      windowEventHandler.handleLinkClick(fakeEvent)
      expect(shell.openExternal).not.toHaveBeenCalled()
      shell.openExternal.reset()

      link.href = '#scroll-me'
      windowEventHandler.handleLinkClick(fakeEvent)
      expect(shell.openExternal).not.toHaveBeenCalled()

  describe "when a form is submitted", ->
    it "prevents the default so that the window's URL isn't changed", ->
      form = document.createElement('form')
      jasmine.attachToDOM(form)

      defaultPrevented = false
      event = new CustomEvent('submit', bubbles: true)
      event.preventDefault = -> defaultPrevented = true
      form.dispatchEvent(event)
      expect(defaultPrevented).toBe(true)

  describe "core:focus-next and core:focus-previous", ->
    describe "when there is no currently focused element", ->
      it "focuses the element with the lowest/highest tabindex", ->
        wrapperDiv = document.createElement('div')
        wrapperDiv.innerHTML = """
          <div>
            <button tabindex="2"></button>
            <input tabindex="1">
          </div>
        """
        elements = wrapperDiv.firstChild
        jasmine.attachToDOM(elements)

        elements.dispatchEvent(new CustomEvent("core:focus-next", bubbles: true))
        expect(document.activeElement.tabIndex).toBe 1

        document.body.focus()
        elements.dispatchEvent(new CustomEvent("core:focus-previous", bubbles: true))
        expect(document.activeElement.tabIndex).toBe 2

    describe "when a tabindex is set on the currently focused element", ->
      it "focuses the element with the next highest/lowest tabindex, skipping disabled elements", ->
        wrapperDiv = document.createElement('div')
        wrapperDiv.innerHTML = """
          <div>
            <input tabindex="1">
            <button tabindex="2"></button>
            <button tabindex="5"></button>
            <input tabindex="-1">
            <input tabindex="3">
            <button tabindex="7"></button>
            <input tabindex="9" disabled>
          </div>
        """
        elements = wrapperDiv.firstChild
        jasmine.attachToDOM(elements)

        elements.querySelector('[tabindex="1"]').focus()

        elements.dispatchEvent(new CustomEvent("core:focus-next", bubbles: true))
        expect(document.activeElement.tabIndex).toBe 2

        elements.dispatchEvent(new CustomEvent("core:focus-next", bubbles: true))
        expect(document.activeElement.tabIndex).toBe 3

        elements.dispatchEvent(new CustomEvent("core:focus-next", bubbles: true))
        expect(document.activeElement.tabIndex).toBe 5

        elements.dispatchEvent(new CustomEvent("core:focus-next", bubbles: true))
        expect(document.activeElement.tabIndex).toBe 7

        elements.dispatchEvent(new CustomEvent("core:focus-next", bubbles: true))
        expect(document.activeElement.tabIndex).toBe 1

        elements.dispatchEvent(new CustomEvent("core:focus-previous", bubbles: true))
        expect(document.activeElement.tabIndex).toBe 7

        elements.dispatchEvent(new CustomEvent("core:focus-previous", bubbles: true))
        expect(document.activeElement.tabIndex).toBe 5

        elements.dispatchEvent(new CustomEvent("core:focus-previous", bubbles: true))
        expect(document.activeElement.tabIndex).toBe 3

        elements.dispatchEvent(new CustomEvent("core:focus-previous", bubbles: true))
        expect(document.activeElement.tabIndex).toBe 2

        elements.dispatchEvent(new CustomEvent("core:focus-previous", bubbles: true))
        expect(document.activeElement.tabIndex).toBe 1

        elements.dispatchEvent(new CustomEvent("core:focus-previous", bubbles: true))
        expect(document.activeElement.tabIndex).toBe 7

  describe "the window:open-locations event", ->
    beforeEach ->
      spyOn(atom.workspace, 'open')
      atom.project.setPaths([])

    describe "when the opened path exists", ->
      it "adds it to the project's paths", ->
        pathToOpen = __filename
        atom.getCurrentWindow().send 'message', 'open-locations', [{pathToOpen}]

        waitsFor ->
          atom.project.getPaths().length is 1

        runs ->
          expect(atom.project.getPaths()[0]).toBe __dirname

    describe "when the opened path does not exist but its parent directory does", ->
      it "adds the parent directory to the project paths", ->
        pathToOpen = path.join(__dirname, 'this-path-does-not-exist.txt')
        atom.getCurrentWindow().send 'message', 'open-locations', [{pathToOpen}]

        waitsFor ->
          atom.project.getPaths().length is 1

        runs ->
          expect(atom.project.getPaths()[0]).toBe __dirname

    describe "when the opened path is a file", ->
      it "opens it in the workspace", ->
        pathToOpen = __filename
        atom.getCurrentWindow().send 'message', 'open-locations', [{pathToOpen}]

        waitsFor ->
          atom.workspace.open.callCount is 1

        runs ->
          expect(atom.workspace.open.mostRecentCall.args[0]).toBe __filename


    describe "when the opened path is a directory", ->
      it "does not open it in the workspace", ->
        pathToOpen = __dirname
        atom.getCurrentWindow().send 'message', 'open-locations', [{pathToOpen}]
        expect(atom.workspace.open.callCount).toBe 0

    describe "when the opened path is a uri", ->
      it "adds it to the project's paths as is", ->
        pathToOpen = 'remote://server:7644/some/dir/path'
        atom.getCurrentWindow().send 'message', 'open-locations', [{pathToOpen}]

        waitsFor ->
          atom.project.getPaths().length is 1

        runs ->
          expect(atom.project.getPaths()[0]).toBe pathToOpen

  describe "when keydown events occur on the document", ->
    it "dispatches the event via the KeymapManager and CommandRegistry", ->
      dispatchedCommands = []
      atom.commands.onWillDispatch (command) -> dispatchedCommands.push(command)
      atom.commands.add '*', 'foo-command': ->
      atom.keymaps.add 'source-name', '*': {'x': 'foo-command'}

      event = KeymapManager.buildKeydownEvent('x', target: document.createElement('div'))
      document.dispatchEvent(event)

      expect(dispatchedCommands.length).toBe 1
      expect(dispatchedCommands[0].type).toBe 'foo-command'

  describe "when an update becomes available", ->
    subscription = null

    afterEach ->
      subscription?.dispose()

    it "invokes onUpdateAvailable listeners", ->
      updateAvailableHandler = jasmine.createSpy("update-available-handler")
      subscription = atom.onUpdateAvailable updateAvailableHandler

      autoUpdater = require('remote').require('auto-updater')
      autoUpdater.emit 'update-downloaded', null, "notes", "version"

      waitsFor ->
        updateAvailableHandler.callCount > 0

      runs ->
        {releaseVersion} = updateAvailableHandler.mostRecentCall.args[0]
        expect(releaseVersion).toBe 'version'

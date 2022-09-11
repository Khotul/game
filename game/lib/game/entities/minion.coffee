Entity = require("../../engine/entity.coffee")
GameEntity = require("./game-entity.coffee")

config = require("config/general")
gameMsg = require("config/game-messages")

class Minion extends GameEntity
  ctype: GameEntity.CTYPE.MINION
  name: "minion",

  constructor: ( x, y, settings) ->
    @reset()
    super( x, y, settings );
    @width = @width || config.minions.width
    @height = @height || config.minions.height
    @size = {x: @width, y: @height}
    @maxHealth = @health;
    @healthBar.height = 4
    @updateHealthBarHealth();
    @currentAnim = @anims.down
    nextNode = ts.game.minionManager.getNodeScaled(@nodePath, @currentNode);
    @setTargetPos(nextNode.x, nextNode.y)
    @loadAnimations()
    @loadShadow()


  reset: () ->
    super();
    if @healthBarImage
      ts.system.container.removeChild(@healthBarImage)
    @race = null
    @target = null
    @souls = 0
    @maxHealth = 0
    @receiveDamageLog = []
    @armor = 0
    @magicResist = 0
    @value = 0
    @level = 0
    @message = ""
    @minionType = null
    @moveType = null
    @team = null
    @owner = null
    @modifiers = []
    @currentNode = 0
    @nodePath = 0
    @lastDamageSource = null
    @cost = 0
    @income = 0
    @imageName = 0
    @range = 0
    @refreshTime = 0
    @healthChanged = false
    @healthBar = {}
    @healthBarImage = null
    @corpseExploded = false
    @distanceTravelled = 0
    @animSpeed = null
    @shadow = null
    @shadowOffset = 0
    @damageTexts = []

  loadAnimations: ->
    imageName = 'minions/' + @imageName
    @zIndex = @zIndex || config.minions.zIndex
    @animSheet = ts.game.cache.getAnimationSheet(imageName, @width, @height, @zIndex)
    @offset = {x: ((@width - 48) / 2), y: ((@height - 48) / 2)}
    if @moveType == "ground"
      @offset.y += config.minions.groundVerticalOffset
    if @moveType == "air"
      @offset.y += config.minions.airVerticalOffset
    animSpeed = @animSpeed || 0.1
    for own animName, animFrames of @frames
      @addAnim(animName, animSpeed, animFrames)

  loadShadow: ->
    if PIXI?
      minionConfig = config.minions
      @shadow = new PIXI.Sprite(PIXI.Texture.fromImage('/img/shadow.png'));
      @shadow.zIndex = minionConfig.shadowZIndex
      if @moveType == "ground"
        @shadow.alpha = minionConfig.groundShadowOpacity
      if @moveType == "air"
        @shadow.alpha = minionConfig.airShadowOpacity
      ts.system.container.addChild(@shadow);
      @shadowOffset = if @moveType == "ground" then minionConfig.groundShadowDistance else minionConfig.airShadowDistance

  update: ->
    ts.log.debug("Calling update on minion ", @minionType, " at pos ", @pos)
    @checkModifiers();
    @checkReachedTarget();
    @fadeDamageText(); #we want it in update so it's as smooth as possible
    super();

  checkReachedTarget: ->
    super()
    #Check if we've reached our target node and if so get the next node in our list.
    if @hasReachedTarget()
      ts.game.dispatcher.emit gameMsg.minionReachedNode, this
      @setTargetNode(@currentNode + 1)

  setTargetNode: (nodeId) ->
    @currentNode = nodeId
    nextNode = ts.game.minionManager.getNodeScaled(@nodePath, nodeId);
    if nextNode?
      @setTargetPos nextNode.x, nextNode.y
    else
      #Minion has reached the end of the map, so kill it and deal damage to the player.
      @lastDamageSource = null; #So the game knows it was killed by the map, not player.
      @kill()


  checkAnim: ->
    if @frozen #When frozen keep same anim and stick in spot
      @currentAnim.rewind()
      return false
    isXVelFaster = Math.abs(@lastVel.x) > Math.abs(@lastVel.y)
    if isXVelFaster
      if @lastVel.x < 0
        @currentAnim = @anims.left
      else
        @currentAnim = @anims.right
    else
      if @lastVel.y < 0
        @currentAnim = @anims.up
      else
        @currentAnim = @anims.down

  draw: ->
    @checkAnim();
    super();
    if @visible
      @updateHealthBarPos();
      @drawHealthBar()
      @drawShadow()

  drawHealthBar: ->
    if !@healthBarImage
      @healthBarImage = new PIXI.Graphics()
      @healthBarImage.zIndex = config.healthBars.zIndex
      @healthBarImage.spawnTime = Date.now()
      ts.system.container.addChild(@healthBarImage)

    if @healthChanged
      borderWidth = 1
      @healthBarImage.clear()

      #Healthy Part (green fill)
      @healthBarImage.beginFill(0x00C800)
      @healthBarImage.drawRect(borderWidth, 0, @healthBar.greenWidth, @healthBar.height + borderWidth * 2)
      @healthBarImage.endFill()

      #Damaged Part (red fill)
      @healthBarImage.beginFill(0xC80000)
      @healthBarImage.drawRect(borderWidth + @healthBar.greenWidth, 0, @healthBar.redWidth, @healthBar.height + borderWidth * 2)
      @healthBarImage.endFill()

      #Border
      @healthBarImage.lineStyle(borderWidth, 0x000000, 1);
      @healthBarImage.drawRect(0, 0, @healthBar.greenWidth + @healthBar.redWidth + borderWidth * 2, @healthBar.height + borderWidth * 2)
      @healthBarImage.lineStyle(0)
      @healthChanged = false

  drawShadow: ->
    if !@shadow
      return false
    @shadow.position.x = Math.round(@drawPos.x + (@width / 2) - (@shadow.width / 2))
    @shadow.position.y = @drawPos.y + @height + @shadowOffset

  drawDamageText: (amount) ->
    if !@damageTexts
      @damageTexts = []
    amount = Math.round(amount) #there aren't any decimal damage values in original TowerStorm I think? however, if someone implements one in their fork, this will be useful.
    textSize = (6 + (amount / @maxHealth()) * 60).toFixed(2) #text size based on damage amount relative to minion's max health
    if textSize > 30
      textSize = 30
    #older PIXI versions do not support fontSize property (something that took me an entire hour of debugging to find out), so we have to inject our size into the font string
    text = new PIXI.Text(amount, {font: "bold " + textSize + "px" + " Arial", fill: "white", stroke: "black", strokeThickness: 3})
    #ts.log.info("Damage text: ", text)
    text.zIndex = config.bullets.zIndex + 1 #we don't want it to be covered by big bullets like flamethrower flames
    text.position.x = @drawPos.x + (@width / 2) - (text.width / 2) + Math.random() * 18 + ((Math.random() * (amount / (@maxHealth()) * 2)))
    text.position.y = @drawPos.y + Math.random() * 15 - Math.random() * 6
    text.spread = (((Math.random() * 100) - (Math.random() * 100)) / 100) + (Math.random() * (amount / (@maxHealth()))) - (Math.random() * (amount / (@maxHealth())))
    #a lot of math random to make it really look like the damage text is flying around
    #based on damage amount, so low damage values will be more grouped together, making the higher ones stand out more
    text.alpha = 1
    text.spawnTime = Date.now()
    ts.system.container.addChild(text)
    @damageTexts.push(text)

  fadeDamageText: -> #we make the tween ourselves so we don't have to rely on external libraries
    if !@damageTexts? || !@damageTexts.length
      return false;
    for text in @damageTexts
      if text? #sometimes the loop runs even if the text is null, probably by the way I'm splicing the array. this is a dirty fix that works perfectly.
        timePassed = Date.now() - text.spawnTime; #by multiplying by timePassed we make it fade quicker exponentially
        text.position.y -= 0.01 * timePassed
        text.position.x += text.spread
        text.alpha -= 0.001 * timePassed
        if text.alpha <= 0
          @damageTexts.splice(@damageTexts.indexOf(text), 1)
          ts.system.container.removeChild(text)

  undrawDamageText: -> #function to clear everything once the minion dies, otherwise it would keep drawing the text
    if !@damageTexts? || !@damageTexts.length
      return false;
    for text in @damageTexts
      ts.system.container.removeChild(text)
    @damageTexts = []

  checkModifiers: ->
    if !@modifiers? || !@modifiers.length
      return false;
    timePassed = ts.system.constantTick;
    modifiersNotFinished = []
    for modifier in @modifiers
      if modifier.update?
        modifier.update(timePassed);
      else if modifier.end?
        modifier.end()
      if modifier.isActive
        modifiersNotFinished.push modifier
    #Remove all modifiers that are finished by creating a new array of those that are still running.
    @modifiers = modifiersNotFinished;

  receiveDamage: (amount, from) ->
    if isNaN(amount)
      throw new Error "Invalid number passed to receiveDamage"
    if @_killed
      return false;
    if from?
      @lastDamageSource = from
    if ts.game.debugMode
      @receiveDamageLog.push({amount: amount, sourceType: from.imageName})
    @drawDamageText(amount)
    super(amount, from)
    @updateHealthBarHealth()

  updateHealthBarHealth: ->
    health = Math.max(0, @health)
    @healthBar.greenWidth = ((@width) * (health / @maxHealth))
    @healthBar.redWidth = ((@width) * (1 - (health / @maxHealth)))
    @healthChanged = true

  updateHealthBarPos: ->
    if @healthBarImage
      @healthBarImage.x = @drawPos.x - 1 #-1 for the border
      @healthBarImage.y = @drawPos.y - 8

  hasModifier: (name) ->
    for modifier in @modifiers
      if modifier.name == name
        return true
    return false

  ###
   *  Doing stuff like slow / poison when a bullet hits this minion
  ###
  injectModifiers: (modifiers) ->
    for modifier in modifiers
      if !@hasModifier(modifier.name) && modifier.inject?
        modifier.inject(@)  #Start the modifier on this minion and push it into it's modifiers array
        @modifiers.push(modifier)

  kill: ->
    ts.log.debug("Killing minion ", @minionType, " at pos ", @pos)
    if @lastDamageSource?
      ts.log.debug("Last damage source is: ", @lastDamageSource.name)
      if @lastDamageSource.name == "bullet"
        ts.log.debug("Killed by bullet ", @lastDamageSource.imageName)
    ts.game.dispatcher.emit gameMsg.minionDied, this, @lastDamageSource;
    super();

  destroy: ->
    if @shadow
      ts.system.container.removeChild(@shadow)
    @undrawDamageText()
    super()

  isKilled: ->
    return @._killed

  canBeShot: ->
    if @_killed
      return false
    if @health <= 0
      return false
    return true


  getSnapshot: (snapshot = {}) ->
    for item in ['damage', 'maxHealth', 'receiveDamageLog', 'value', 'team', 'currentNode', 'nodePath', 'cost', 'income',  'range']
      snapshot[item] = @[item]
    super(snapshot)

  setVisible: (visible) ->
    if @shadow
      @shadow.visible = visible
    super(visible)


module.exports = Minion

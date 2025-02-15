module game

require files
require app
require sound_names
require entities

require daslib/algorithm
require math
require daslib/json_boost
require fio

var frame_time = 1.0

let DOOR_SOUND_PLAYBACK_RATE = 18000
let DOOR_SOUND_RADIUS = 10.0     // how far away door sound can be heard (in tiles)
let DOOR_OPEN_SPEED = 2.0        // how fast door opens (in tiles per second)
let DOOR_CLOSE_SPPED = 2.0       // how fast door closes (in tiles per second)
let DOOR_STAYS_CLOSED = 2.0      // how long door stays closed (in seconds)

struct Animation
    sprites : array<int>
    spriteIndex : int
    timer : float
    loop : bool

def Animation ( SPRITES:array<int>; LOOP:bool = false )
    var self : Animation
    with self
        sprites := SPRITES
        spriteIndex = 0
        timer = 0.
        loop = LOOP
    return <- self

enum Category
    nothing
    prop
    enemy

struct public Entity
    category : Category
    spriteIndex : int
    animation   : Animation?
    direction   : int
    orientable  : bool

var public object_plane : Entity[64*64]

enum EnemyCategory
    guard
    dog
    officer
    ss
    mutant

struct public EnemyClass
    enemyCategory : EnemyCategory
    spriteIndex : int
    deathSprites : array<int>
    orientable : bool

let enemyClasses <- [[EnemyClass
// guard
    spriteIndex = 50,
    deathSprites <- [{auto 90; 91; 92; 93; 95}];
// dog
    spriteIndex = 99,
    deathSprites <- [{auto 131; 132; 133; 134}];
// officer
    spriteIndex = 238,
    deathSprites <- [{auto 279; 280; 281; 283; 284}];
// ss
    spriteIndex = 138,
    deathSprites <- [{auto 179; 180; 181; 183}];
// mutant
    spriteIndex = 187,
    deathSprites <- [{auto 228; 229; 230; 232; 233}]
]]

struct public Enemy : Entity
    enemyCategory : EnemyCategory
    patrolling : bool
    alive : bool

var public enemy_plane : Enemy[64*64]

def startAnimation ( var entity:Entity; ANIMATION:Animation? )
    entity.animation = ANIMATION
    entity.spriteIndex = entity.animation.sprites[0]

def die ( var enemy:Enemy)
    enemy.alive = false
    enemy.orientable = false
    enemy |> startAnimation(new Animation(enemyClasses[int(enemy.enemyCategory)].deathSprites))

def getPlayerRelativeCoordinates ( X,Y : int ) : tuple<rx:float;ry:float;orx:float;ory:float>
    let ox = float(X) + 0.5
    let oy = float(Y) + 0.5
    let orx = ox - player.x
    let ory = oy - player.y
    let rx =  orx * player.dx + ory * player.dy
    let ry = -orx * player.dy + ory * player.dx
    return [[auto rx,ry,orx,ory]]

struct public Player
    x, y : float
    dx, dy : float
    silverKey : bool
    goldKey : bool
    speed : float = 0.065
    speed_a : float = 0.05
    radius : float = 0.25
    moveForwars : bool = false
    moveBackward : bool = false
    strafeLeft : bool = false
    strafeRight : bool = false
    turnLeft : bool = false
    turnRight : bool = false
    turnAngle : float = 0.0
    weaponSprite : int = 421
    weaponAnimation : Animation?

def canMoveTo ( self:Player; X,Y:float )
    with self
        let r = radius
        let fx = X % 1.
        let ix = floori(X)
        let fy = Y % 1.
        let iy = floori(Y)
        if collision_plane[iy*64+ix]
            return false
        if fx < r
            if collision_plane[iy*64+ix-1]
                return false
            if fy < r && collision_plane[(iy-1)*64+ix-1]
                return false
            if fy > 1.-r && collision_plane[(iy+1)*64+ix-1]
                return false
        if fx > 1.-r
            if collision_plane[iy*64+ix+1]
                return false
            if fy < r && collision_plane[(iy-1)*64+ix+1]
                return false
            if fy > 1.-r && collision_plane[(iy+1)*64+ix+1]
                return false
        if fy < r && collision_plane[(iy-1)*64+ix]
            return false
        if fy > 1.-r && collision_plane[(iy+1)*64+ix]
            return false
        return true

def move ( var self:Player; length,sideways:float )
    with self
        let oldx = floori(x)
        let oldy = floori(y)
        let X = x + dx * length - dy * sideways
        let Y = y + dy * length + dx * sideways
        if self |> canMoveTo(X, y)
            x = X
        if self |> canMoveTo(x, Y)
            y = Y
        let newx = floori(x)
        let newy = floori(y)
        if newx != oldx || newy != oldy
            //player.collect(newx, newy)
            // shouldDrawMap = true
            pass

def turn ( var self:Player; alpha:float )
    with self
        let DX = dx * cos(alpha) - dy * sin(alpha)
        dy = dx * sin(alpha) + dy * cos(alpha)
        dx = DX
        let len = sqrt(dx*dx + dy*dy)
        dx /= len
        dy /= len

def update ( var self:Player )
    with self
        var changed = false
        if is_key_pressed(VK_RIGHT)
            turnAngle += 1.
        if is_key_pressed(VK_LEFT)
            turnAngle -= 1.
        if turnAngle != 0.
            self |> turn(turnAngle * speed_a * frame_time)
            turnAngle = 0.
            changed = true
        var forward = 0.
        var sideways = 0.
        if is_key_pressed(VK_UP)
            forward += speed
        if is_key_pressed(VK_DOWN)
            forward -= speed
        if is_key_pressed(VK_A)
            sideways -= speed
        if is_key_pressed(VK_D)
            sideways += speed
        if forward != 0.
            if sideways != 0.
                self |> move(frame_time * forward / sqrt(2.), frame_time * sideways / sqrt(2.))
            else
                self |> move(frame_time * forward, 0.)
            changed = true
        elif sideways != 0.
            self |> move(0., frame_time * sideways)
            changed = true
        if weaponAnimation != null
            assume a = weaponAnimation
            a.timer += 1. / 6. * frame_time
            if a.timer >= 1.
                a.timer = 0.
                if a.spriteIndex >= a.sprites |> length - 1
                    weaponAnimation = null
                    weaponSprite = 421
                else
                    a.spriteIndex += 1
                    weaponSprite = a.sprites[a.spriteIndex]
        if is_key_pressed(VK_SPACE)
            player |> activate()
        if is_key_pressed(VK_LCONTROL) || is_key_pressed(VK_RCONTROL)
            player |> shoot()

def shoot ( var self:Player )
    with self
        if weaponAnimation == null
            play_game_sound(SoundName ATKPISTOLSND)
            weaponAnimation = new Animation([{int 422; 423; 424; 425}])
            let d = zIndex[int(pixelWidth) / 2]
            for Y in range(64)
                for X in range(64)
                    let ofs = X + Y*64
                    if !visibility_plane[ofs]
                        continue
                    if enemy_plane[ofs].category == Category nothing
                        continue
                    var prc = getPlayerRelativeCoordinates(X, Y)
                    if prc.rx < 0.
                        continue
                    if prc.rx >= d
                        continue
                    if abs(prc.ry) <= .3 && enemy_plane[ofs].alive
                        // flash = new Flash(.5, 0, 0)
                        enemy_plane[ofs] |> die()
                        return

def isTooCloseToDoor(var self:Player; X,Y:int)
    with self
        let ix = floori(x)
        let iy = floori(y)
        if (X==ix) && (Y==iy)
            return true
        if abs(float(X)+0.5-x)<=radius+0.5 && abs(float(Y)+0.5-y)<=radius+0.5
            return true
        return false

def activate ( var self:Player)
    with self
        var X = floori(x)
        var Y = floori(y)
        var DX = 0
        var DY = 0
        if abs(dx) >= abs(dy)
            DX = dx >= 0. ? 1 : -1
            X += DX
        else
            DY = dy >= 0. ? 1 : -1
            Y += DY
        let m0 = int(level.plane0[Y*64+X])
        let m1 = int(level.plane1[Y*64+X])
        if m0==21 && DX!=0
            // elevator
            loadNextLevel()
        elif m0>=90 && m0<=101
            // door
            if m0==92 || m0==93 && !goldKey
                // gold-locked door
                print("gold-locked door\n")
                return
            if m0==94 || m0==95 && !silverKey
                // silver-locked door
                print("silver-locked door\n")
                return
            assume timer = timer_plane[Y*64+X]
            if !timer.active
                timer = [[Timer
                    t = 0.,
                    opening = true,
                    active = true,
                    isDoor = true
                ]]
                play_game_sound_2d(SoundName OPENDOORSND, float2(X,Y)+float2(0.5), DOOR_SOUND_RADIUS, DOOR_SOUND_PLAYBACK_RATE)
        elif m1 == 98
            // pushwall
            assume timer = timer_plane[Y*64+X]
            if !timer.active && int(level.plane0[(Y+DY)*64+X+DX]) >= 106
                // there is no active timer for this wall, and it can move backwards
                timer = [[Timer
                    t = 0.,
                    dx = DX,
                    dy = DY,
                    steps = 2,
                    opening = true,
                    active = true,
                    isWall = true
                ]]
                play_game_sound_2d(SoundName OPENDOORSND, float2(X,Y)+float2(0.5), DOOR_SOUND_RADIUS)
        else
            assume timer = timer_plane[Y*64+X]
            if !timer.active
                timer = [[Timer
                    t = 0.5,
                    active = true
                ]]
                play_game_sound_2d(SoundName PUSHWALLSND, float2(X,Y)+float2(0.5), DOOR_SOUND_RADIUS)

var public player = Player()

struct Timer
    t : float
    dx, dy : int
    steps : int
    opening : bool
    active : bool
    isDoor : bool
    isWall : bool

var timer_plane : Timer[64*64]

var collision_plane : bool[64*64]

var visibility_plane : bool[64*64]

var public zIndex : array<float>

var fov = 1.
var pixelWidth = 320.
var pixelHeight = 200.
var wallHeight = float(pixelWidth) / (2. * fov)

var public level : Level
var public levelIndex = 0

def setupLevel ( index:int )
    print("LOADING LEVEL {index}\n}")
    level := Levels[index]
    delete object_plane
    delete enemy_plane
    for b in collision_plane
        b = false
    for t in timer_plane
        t.active = false
    player = Player()
    for y in range(64)
        for x in range(64)
            // structual
            let m0 = int(level.plane0[x + y * 64])
            if m0 <= 63
                // wall
                collision_plane[x + y * 64] = true
            elif 90 <= m0 && m0 <= 101
                // door
                collision_plane[x + y * 64] = true
            // entities
            let m1 = int(level.plane1[x + y * 64])
            if isPlayer(m1)
                // player
                player.x = float(x) + 0.5
                player.y = float(y) + 0.5
                getEntityDirection(m1-19,player.dx,player.dy)
            elif isProp(m1)
                object_plane[x + y * 64] = [[Entity
                    category = Category prop,
                    spriteIndex = m1-21
                ]]
                if isBlocking(m1)
                    collision_plane[x + y * 64] = true
            elif isPushWall(m1)
                pass
                // pushwall
                // score.totalSecrets ++
            elif isDeadGuard(m1)
                // dead guard
                object_plane[x + y * 64] = [[Entity
                    category = Category prop,
                    spriteIndex = 95
                ]]
            elif isEnemy(m1)
                var category : EnemyCategory
                var patrolling = false
                var orientable = true
                if isStandingGuard(m1)
                    category = EnemyCategory guard
                elif isPatrollingGuard(m1)
                    category = EnemyCategory guard
                    patrolling = true
                elif isStandingDog(m1)
                    category = EnemyCategory dog
                elif isPatrollingDog(m1)
                    category = EnemyCategory dog
                    patrolling = true
                elif isStandingSS(m1)
                    category = EnemyCategory ss
                elif isPatrollingSS(m1)
                    category = EnemyCategory ss
                    patrolling = true
                elif isStandingMutant(m1)
                    category = EnemyCategory mutant
                elif isPatrollingMutant(m1)
                    category = EnemyCategory mutant
                    patrolling = true
                // todo: add bosses
                enemy_plane[x + y * 64] = [[Enemy
                    category = Category enemy,
                    enemyCategory = category,
                    patrolling = patrolling,
                    spriteIndex = enemyClasses[int(category)].spriteIndex,
                    alive = true,
                    orientable = orientable,
                    direction = m1 & 3
                ]]
            /*
            elif m1 >= 108

                elif m1==160
                    things |> push <| new FakeHitlerEnemy(x,y)
                elif m1==178
                    things |> push <| new HitlerEnemy(x,y)
                elif m1==179
                    things |> push <| new FettgesichtEnemy(x,y)
                elif m1==196
                    things |> push <| new SchabbsEnemy(x,y)
                elif m1==197
                    things |> push <| new GretelEnemy(x,y)
                elif m1==198
                    things |> push <| new HansEnemy(x,y)
                elif m1==199
                    things |> push <| new OttoEnemy(x,y)
                elif m1>=224 && m1<228
                    // ghost
                    var ghost = new Thing(x,y,0)
                    let spriteIndex = 288 + 2 * (m1-224)
                    ghost->startAnimation ( new Animation([{int spriteIndex; spriteIndex + 1}], true) )
                    things |> push <| ghost
            */

def loadNextLevel
    levelIndex ++
    setupLevel(levelIndex)

def updateThings
    for enemy in enemy_plane
        if enemy.category == Category nothing
            continue
        if enemy.animation != null
            enemy.animation.timer += 1. / 6. * frame_time
            if enemy.animation.timer >= 1.0
                enemy.animation.timer = 0.
                if enemy.animation.spriteIndex >= enemy.animation.sprites |> length - 1
                    if enemy.animation.loop
                        // animation loops
                        enemy.animation.spriteIndex = 0
                    else
                        // animation ended (delete?)
                        enemy.animation = null
                        return
                else
                    enemy.animation.spriteIndex += 1
                enemy.spriteIndex = enemy.animation.sprites[enemy.animation.spriteIndex]

def updatetimer_plane
    for timer,index in timer_plane,count()
        if !timer.active
            continue
        let X = index & 63
        let Y = index >> 6
        if timer.isDoor
            if timer.opening
                if timer.t < 1.
                    timer.t += DOOR_OPEN_SPEED / 64. * frame_time
                else
                    timer.t += 1. / 60. * frame_time
                if timer.t >= 1.
                    collision_plane[index] = false
                if timer.t >= DOOR_STAYS_CLOSED
                    timer.t = DOOR_STAYS_CLOSED
                    timer.opening = false
            else
                if timer.t < 1.
                    timer.t -= DOOR_CLOSE_SPPED / 64. * frame_time
                else
                    timer.t -= 1./ 60. * frame_time
                if timer.t <= 1.
                    if !collision_plane[index]
                        if player |> isTooCloseToDoor(X, Y)
                            timer.t = DOOR_STAYS_CLOSED
                            // print("TOO CLOSE TO DOOR {player.x} {player.y} \n")
                        else
                            play_game_sound_2d(SoundName CLOSEDOORSND, float2(X,Y)+float2(0.5), DOOR_SOUND_RADIUS, DOOR_SOUND_PLAYBACK_RATE)
                            collision_plane[index] = true
                if timer.t <= 0.
                    timer.t = 0.
                    timer.active = false
        elif timer.isWall
            timer.t += 1. / 60. * frame_time
            if timer.t >= 1.
                let DX = timer.dx
                let DY = timer.dy
                let wallValue = level.plane0[index]
                level.plane0[index] = level.plane0[(X-DX) + (Y-DY) * 64]
                level.plane0[(X+DX) + (Y+DY) * 64] = wallValue
                level.plane1[index] = uint16(0)
                collision_plane[index] = false
                collision_plane[(X+DX) + (Y+DY) * 64] = true
                timer.steps -= 1
                if timer.steps>0 && !collision_plane[(X+2*DX) + (Y+2*DY) * 64]
                    // wall moves one more step
                    level.plane1[(X+DX) + (Y+DY) * 64] = uint16(98)
                    timer.t = 0.
                    timer_plane[(X+DX) + (Y+DY) * 64] = timer
                timer.active = false
        else
            // any random timer
            timer.t -= 1. / 60. * frame_time
            if timer.t <= 0.
                timer.t = 0.
                timer.active = false

struct Location
    x, y, dx, dy : float

var ENABLE_CHEAT_CODEDS = true

def updatePlayer
    player |> update()
    // note: the section bellow is for debugging only. It allows to save and load player position
    if !ENABLE_CHEAT_CODEDS
        return
    if is_key_pressed(VK_F2)
        fopen("{get_das_root()}/temp/player.json","wb") <| $ ( f )
            if f != null
                to_log(LOG_INFO,"player at {player.x} {player.y} {player.dx} {player.dy}\n")
                let loc = JV([[Location x=player.x, y=player.y, dx=player.dx, dy=player.dy]])
                let txt = write_json(loc)
                f |> fwrite(txt)
                to_log(LOG_INFO, "saved\n")
    if is_key_pressed(VK_F3)
        fopen("{get_das_root()}/temp/player.json","rb") <| $ ( f )
            if f != null
                let txt = fread(f)
                var error = ""
                var jv = read_json(txt, error)
                if jv != null
                    to_log(LOG_INFO, "loaded\n")
                    var loc = from_JV(jv, type<Location>)
                    player.x = loc.x
                    player.y = loc.y
                    player.dx = loc.dx
                    player.dy = loc.dy
                    to_log(LOG_INFO,"player at {player.x} {player.y} {player.dx} {player.dy}\n")
    if is_key_pressed(VK_F10)
        loadNextLevel()


/*
    // update flashing palette
    if (flash !== undefined) {
        flash.timer += 1;
        if (flash.timer <= flash.duration / 3) {
            flashPalette(flash.red / 2, flash.green / 2, flash.blue / 2);
        } else if (flash.timer <= 2 * flash.duration / 3) {
            flashPalette(flash.red, flash.green, flash.blue);
        } else if (flash.timer <= flash.duration) {
            flashPalette(flash.red / 2, flash.green / 2, flash.blue / 2);
        } else {
            flashPalette(0, 0, 0);
            flash = undefined
        }
    }

    if (fps60) {
        // run at 60fps
        draw();
    } else if (drawNextFrame = !drawNextFrame) {
        // run at 30 fps
        draw();
    }

    // call the function again on next frame
    requestAnimationFrame(update);
}
*/

def public updateGame(dt:float)
    frame_time = dt / 16.0
    updatePlayer()
    updatetimer_plane()
    updateThings()


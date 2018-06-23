module WaterWars.Client.Render.Display where

import ClassyPrelude
import Graphics.Gloss as Gloss
import Sound.ProteaAudio

import WaterWars.Client.Render.Config
import WaterWars.Client.Render.Animation
import WaterWars.Client.Render.State
import WaterWars.Client.Render.Terrain.Solid

import WaterWars.Client.Resources.Resources

import WaterWars.Core.Game

-- |Convert a game state into a picture
renderIO :: WorldSTM -> IO Picture
renderIO (WorldSTM tvar) = do
    world <- readTVarIO tvar
    when (isJust $ shoot (worldInfo world)) $ 
        soundPlay (shootSound . resources $ renderInfo world) 1 1 0 1
    return $ render world

-- TODO: render WorldInfo in combination with RenderInfo
render :: World -> Picture
render World {..} = 
    let RenderInfo {..} = renderInfo
        Resources {..} = resources
    in Gloss.pictures
    (  [backgroundTexture]
    ++ [mantaPicture]
    ++ toList solidPictures
    ++ playerPictures
    ++ toList projectilePictures
    )

  where
    allPlayers :: [InGamePlayer]
    allPlayers =
        maybeToList (player worldInfo) ++ toList (otherPlayers worldInfo)

    playerPictures :: [Picture]
    playerPictures = map (inGamePlayerToPicture renderInfo) allPlayers

    projectilePictures :: Seq Picture
    projectilePictures =
        map (projectileToPicture renderInfo) (projectiles worldInfo)

    solidPictures :: Seq Picture
    solidPictures = map solidToPicture (solids renderInfo)

    mantaPicture :: Picture
    mantaPicture =
        backgroundAnimationToPicture renderInfo (mantaAnimation renderInfo)

inGamePlayerColor :: Color
inGamePlayerColor = red

solidToPicture :: Solid -> Picture
solidToPicture solid =
    uncurry translate (solidCenter solid)
        $ scale blockSize           blockSize
        $ scale (1 / blockImgWidth) (1 / blockImgHeight)
        $ solidTexture solid

inGamePlayerToPicture :: RenderInfo -> InGamePlayer -> Picture
inGamePlayerToPicture RenderInfo {..} InGamePlayer {..} =
    let Resources {..} = resources
        Location (x, y)    = playerLocation
        directionComponent = case playerLastRunDirection of
            RunLeft  -> -1
            RunRight -> 1
        maybeAnimation = lookup playerDescription playerAnimations
        Animation {..} =
            playerToAnimation $ fromMaybe defaultPlayerAnimation maybeAnimation
    in  translate (blockSize * x) (blockSize * y + blockSize * playerHeight / 2)
        $ color inGamePlayerColor
        $ scale blockSize          blockSize
        $ scale playerWidth        playerHeight
        $ scale (1 / mermaidWidth) (1 / mermaidHeight)
        $ scale directionComponent 1 (headEx animationPictures)


projectileToPicture :: RenderInfo -> Projectile -> Picture
projectileToPicture RenderInfo {..} p = translate (x * blockSize)
                                                  (y * blockSize)
                                                  (projectileTexture resources)
    where Location (x, y) = projectileLocation p

countdownToPicture :: RenderInfo -> Int -> Picture
countdownToPicture RenderInfo {..} tick = translate 0 100 pic
    where 
        Resources {..} = resources
        pic
            | tick >= 150 = countdownTextures `indexEx` 0
            | tick >= 100 = countdownTextures `indexEx` 1
            | tick >= 50 = countdownTextures `indexEx` 2
            | tick >= 0  = countdownTextures `indexEx` 3
            | otherwise = error "countdownToPicture: tick is negative"

backgroundAnimationToPicture :: RenderInfo -> BackgroundAnimation -> Picture
backgroundAnimationToPicture _ BackgroundAnimation {..} = translate x y
    $ scale scaleFactor 1 pic
  where
    scaleFactor = case direction of 
        RightDir -> -1
        LeftDir -> 1
    pic             = displayAnimation animation
    Location (x, y) = location

displayAnimation :: Animation -> Picture
displayAnimation Animation {..} = headEx animationPictures

{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE MonoLocalBinds #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}

module WaterWars.Server.GameNg (runGameTick, gameTick) where

import ClassyPrelude hiding (Reader, ask, asks) -- hide MTL functions reexported by prelude
import WaterWars.Core.GameState
import WaterWars.Core.GameMap
import WaterWars.Core.GameAction
import WaterWars.Core.Physics
import WaterWars.Core.PhysicsConstants
import Control.Eff.State.Strict
import Control.Eff.Reader.Strict
import Control.Eff
import Data.Array.IArray
import WaterWars.Core.Terrain.Block

runGameTick :: GameMap -> GameState -> Map Player Action -> GameState
runGameTick gameMap gameState gameAction =
    run
        . execState gameState
        . runReader gameMap
        . runReader gameAction
        $ gameTick

gameTick
    :: ( Member (State GameState) e
       , Member (Reader (Map Player Action)) e
       , Member (Reader GameMap) e
       )
    => Eff e ()
gameTick = do
    mapMOverPlayers modifyPlayerByAction
    moveProjectiles
    mapMOverPlayers modifyPlayerByEnvironment
    mapMOverPlayers movePlayer
    return ()

-- | Moves all projectiles in the game. This is effectful since the movement
--   depends on the whole state
moveProjectiles :: (Member (State GameState) e) => Eff e ()
moveProjectiles = do
    Projectiles projectiles <- gets gameProjectiles
    let newProjectiles = map moveProjectile projectiles
    modify $ \s -> s { gameProjectiles = Projectiles newProjectiles }

moveProjectile :: Projectile -> Projectile
moveProjectile (projectile@Projectile {..}) = projectile
    { projectileLocation = moveLocation projectileVelocity projectileLocation
    }

-- move player according to its velociy, but also bound it.
movePlayer :: Member (Reader GameMap) e => InGamePlayer -> Eff e InGamePlayer
movePlayer player@InGamePlayer {..} = do
    blocks <- asks $ terrainBlocks . gameTerrain
    let targetLocation = moveLocation playerVelocity playerLocation
    let targetBlock    = getBlock targetLocation
    let isTargetBlockSolid = inRange (bounds blocks) targetBlock
            && isSolid (blocks ! targetBlock)
    let realTargetLocation = if isTargetBlockSolid
            then
                let Location      (x, _) = targetLocation
                    BlockLocation (_, y) = targetBlock
                in  Location (x, fromIntegral y + 0.5)
            else targetLocation
    let realPlayerVelocity = if isTargetBlockSolid
            then velocityOnGround playerVelocity
            else playerVelocity
    return player { playerLocation = realTargetLocation
                  , playerVelocity = realPlayerVelocity
                  }

isPlayerOnGround :: Member (Reader GameMap) e => InGamePlayer -> Eff e Bool
isPlayerOnGround InGamePlayer {..} = do
    blocks <- asks $ terrainBlocks . gameTerrain
    let Location (x, y) = playerLocation
    let blockBelowFeet  = BlockLocation (round x, round $ y - 0.001)
    return $ inRange (bounds blocks) blockBelowFeet && isSolid
        (blocks ! blockBelowFeet)

-- | Function that includes the actions into a player-state
modifyPlayerByAction
    :: (Member (Reader (Map Player Action)) e, Member (Reader GameMap) e)
    => InGamePlayer
    -> Eff e InGamePlayer
modifyPlayerByAction player = do
    actionMap :: Map Player Action <- ask
    let action =
            fromMaybe noAction $ lookup (playerDescription player) actionMap
    isOnGround <- isPlayerOnGround player -- TODO: deduplicate
    return
        . modifyPlayerByRunAction isOnGround action
        . modifyPlayerByJumpAction isOnGround action
        $ player

modifyPlayerByJumpAction :: Bool -> Action -> InGamePlayer -> InGamePlayer
modifyPlayerByJumpAction onGround action player@InGamePlayer {..} =
    fromMaybe player $ do -- maybe monad
        unless onGround Nothing
        JumpAction <- jumpAction action
        return $ setPlayerVelocity (jumpVector playerVelocity) player

modifyPlayerByRunAction :: Bool -> Action -> InGamePlayer -> InGamePlayer
modifyPlayerByRunAction onGround action player@InGamePlayer {..} =
    fromMaybe player $ do -- maybe monad
        RunAction runDirection <- runAction action
        return $ setPlayerVelocity
            (velocityBoundX runSpeed $ runVector onGround runDirection ++ playerVelocity)
            player

-- do gravity, bounding, ...
modifyPlayerByEnvironment
    :: Member (Reader GameMap) r => InGamePlayer -> Eff r InGamePlayer
modifyPlayerByEnvironment p = do
    isOnGround <- isPlayerOnGround p
    return
        . modifyPlayerVelocity (boundVelocityVector maxVelocity)
        . verticalDragPlayer isOnGround
        . gravityPlayer
        $ p

gravityPlayer :: InGamePlayer -> InGamePlayer
gravityPlayer = acceleratePlayer gravityVector

-- TODO: better drag with polar coordinates
verticalDragPlayer :: Bool -> InGamePlayer -> InGamePlayer
verticalDragPlayer onGround player@InGamePlayer {..} =
    let VelocityVector vx vy = playerVelocity
        dragFactor = if onGround then verticalDragGround else verticalDragAir
    in  setPlayerVelocity (VelocityVector (vx * dragFactor) vy) player

-- CUSTOM UTILITY FUNCTIONS

mapMOverPlayers
    :: (Member (State GameState) e, Member (Reader GameMap) e)
    => (InGamePlayer -> Eff e InGamePlayer)
    -> Eff e ()
mapMOverPlayers mapping = do
    InGamePlayers players <- gets inGamePlayers
    newPlayers            <- mapM mapping players
    modify $ \s -> s { inGamePlayers = InGamePlayers newPlayers }


-- GENERAL UTILITY FUNCTIONS

asks :: Member (Reader s) r => (s -> a) -> Eff r a
asks f = map f ask
{-# INLINE asks #-}

gets :: Member (State s) r => (s -> a) -> Eff r a
gets f = map f get
{-# INLINE gets #-}
-- TODO: implement with lenses??

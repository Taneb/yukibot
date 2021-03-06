-- |Types for IRC bots.
module Network.IRC.Asakura.Types where

import Control.Concurrent.STM     (TVar, atomically, newTVar)
import Control.Monad.IO.Class     (MonadIO, liftIO)
import Control.Monad.Trans.Reader (ReaderT)
import Data.ByteString            (ByteString)
import Data.Map                   (Map)
import Data.Text                  (Text)
import Network.IRC.Client.Types   (EventType, IRC, IRCState, UnicodeEvent)

import qualified Data.Map as M

-- *State

-- |The bot: a thin wrapper over some globally shared state.
type Bot a = ReaderT BotState IO a

data BotState = BotState
    { _connections :: TVar [(ByteString, IRCState)]
    -- ^We abstract over a particular IRC client by instead dealing
    -- with a map from network names to individual client states,
    -- which we can update in order to communicate with clients.
    --
    -- Furthermore, this is behind a TVar so we can connect to new
    -- things at runtime.
    , _defHandlers :: TVar [AsakuraEventHandler]
    -- ^Default event handlers added to all new connections.
    , _keyStore :: Map Text Text
    -- ^Read-only key-value store for global configuration.
    }

-- |Construct a new bot state
newBotState :: MonadIO m => m BotState
newBotState = do
  tvarC  <- liftIO . atomically . newTVar $ []
  tvarDH <- liftIO . atomically . newTVar $ []
  return BotState { _connections = tvarC
                  , _defHandlers = tvarDH
                  , _keyStore = M.empty
                  }

-- *Events

-- |An irc-client event handler, lifted to run in the Asakura
-- context. Fields are as in irc-client.
data AsakuraEventHandler = AsakuraEventHandler
    { _description :: Text
    , _matchType   :: EventType
    , _eventFunc   :: IRCState -> UnicodeEvent -> Bot (IRC ())
    , _appliesTo   :: ByteString -> Text -> Bot Bool
    -- ^Check if the event handler applies to this network/channel
    , _appliesDef  :: ByteString -> Bot Bool
    -- ^Whether the handler applies outside of a channel
    }

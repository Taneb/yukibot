{-# LANGUAGE OverloadedStrings #-}

-- |Initial network state: networks, nicks, nickserv passwords, and
-- channels.
module Yukibot.Plugins.Initialise
    ( InitialCfg
    , initialise
    , initialiseWithState
    ) where

import Control.Applicative        ((<$>), (<*>))
import Control.Monad              (when, void)
import Control.Monad.IO.Class     (MonadIO, liftIO)
import Control.Monad.Trans.Reader (runReaderT)
import Data.Aeson                 (FromJSON(..), ToJSON(..), Value(..), (.=), (.:), (.:?), (.!=), object)
import Data.Default.Class         (Default(..))
import Data.ByteString.Char8      (pack)
import Data.Map                   (Map)
import Data.Maybe                 (catMaybes)
import Data.Monoid                ((<>))
import Data.Text                  (Text)
import Network.IRC.Asakura        (addNetwork)
import Network.IRC.Asakura.Types  (Bot, BotState)
import Network.IRC.Client         (Message(Numeric, Privmsg, Join), connect, connectWithTLS, defaultIRCConf, send)
import Network.IRC.Client.Types   (EventType(ENumeric), Event(_message), EventHandler(..), InstanceConfig(_eventHandlers))

import qualified Data.Map as M

-- *State

newtype InitialCfg = IS { _networks :: Map String NetworkState }

instance FromJSON InitialCfg where
    parseJSON = fmap IS . parseJSON

instance ToJSON InitialCfg where
    toJSON = toJSON . _networks

instance Default InitialCfg where
    def = IS $ M.fromList [("irc.freenode.net", freenode)]
        where freenode = NS { _nick     = "yukibot"
                            , _port     = 7000
                            , _tls      = True
                            , _nickserv = Nothing
                            , _channels = []
                            }

data NetworkState = NS
    { _nick     :: Text
    , _port     :: Int
    , _tls      :: Bool
    , _nickserv :: Maybe Text
    , _channels :: [Text]
    }

instance FromJSON NetworkState where
    parseJSON (Object v) = NS <$> v .:  "nick"
                              <*> v .:? "port" .!= 6667
                              <*> v .:? "tls" .!= False
                              <*> v .:? "nickservPassword"
                              <*> v .:? "channels" .!= []
    parseJSON _ = fail "Expected object"

instance ToJSON NetworkState where
    toJSON ns = object . catMaybes $ [ Just $ "nick"     .= _nick ns
                                     , Just $ "port"     .= _port ns
                                     , Just $ "tls"      .= _tls ns
                                     , ("nickservPassword" .=) <$> _nickserv ns
                                     , Just $ "channels" .= _channels ns
                                     ]

-- *Application

-- |Connect to all default networks, auth with nickservs, and join
-- channels.
initialise :: InitialCfg -> Bot ()
initialise = mapM_ goN . M.toList . _networks
    where goN (hostname, ns) = do
            -- Connect to the network
            cconf <- if _tls ns
                    then connectWithTLS (pack hostname) (_port ns) 1
                    else connect        (pack hostname) (_port ns) 1

            let iconf  = defaultIRCConf $ _nick ns
            let iconf' = iconf { _eventHandlers = onWelcome ns : _eventHandlers iconf }

            -- Add it to the bot
            void $ addNetwork cconf iconf'

          -- Wait for the welcome message, and then join channels
          onWelcome ns = EventHandler { _description = "Apply initial state"
                                      , _matchType   = ENumeric
                                      , _eventFunc   = goC ns
                                      }

          goC ns ev = let Numeric n _ = _message ev
                      in when (n == 1) $ do
                           -- Auth with nickserv
                           case _nickserv ns of
                             Just pass -> send . Privmsg "nickserv" . Right $ "IDENTIFY " <> pass
                             Nothing   -> return ()

                           -- Join channels
                           mapM_ (send . Join) $ _channels ns

-- |Initialise with the provided bot state
initialiseWithState :: MonadIO m => BotState -> InitialCfg -> m ()
initialiseWithState bs = liftIO . flip runReaderT bs . initialise

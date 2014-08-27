{-# LANGUAGE OverloadedStrings #-}

-- |Common utility functions for plugins.
module Yukibot.Utils where

import Control.Applicative    ((<$>))
import Control.Exception      (catch)
import Control.Lens           ((&), (.~), (^.))
import Control.Monad          (guard)
import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.ByteString        (ByteString, isInfixOf)
import Data.ByteString.Lazy   (toStrict)
import Data.Maybe             (fromMaybe)
import Data.String            (IsString(..))
import Data.Text              (unpack)
import Data.Text.Encoding     (decodeUtf8)
import Network.HTTP.Client    (HttpException)
import Network.Wreq
import Network.URI            (URI(..), URIAuth(..), uriToString)

-- |Download an HTML document. Return (Just html) if we get a 200
-- response code, and a html-y content-type. This follows redirects.
--
-- This decodes the result as UTF-8. If another encoding is desired,
-- use 'fetchHttp' directly.
fetchHtml :: MonadIO m => URI -> m (Maybe String)
fetchHtml = flip fetchHtml' defaults

-- |Like 'fetchHtml', but accepts a username and password.
--
-- This decodes the result as UTF-8. If another encoding is desired,
-- use 'fetchHttp' directly.
fetchHtmlWithCreds :: MonadIO m => URI -> String -> String -> m (Maybe String)
fetchHtmlWithCreds url user pass = fetchHtml' url opts
    where opts = defaults & auth .~ basicAuth (fromString user) (fromString pass)

-- |Like 'fetchHtml', but takes options (in addition to following
-- redirects).
--
-- This decodes the result as UTF-8. If another encoding is desired,
-- use 'fetchHttp' directly.
fetchHtml' :: MonadIO m => URI -> Options -> m (Maybe String)
fetchHtml' url opts = do
  res <- fetchHttp' url opts

  return $ do
    response <- res

    guard $ "html" `isInfixOf` (response ^. responseHeader "Content-Type")

    Just . unpack . decodeUtf8 $ response ^. responseBody

-- |Download something over HTTP, returning (Just response) on a 200
-- response code. This follows redirects.
fetchHttp :: MonadIO m => URI -> m (Maybe (Response ByteString))
fetchHttp = flip fetchHttp' defaults

-- |Like 'fetchHttp', but also takes options (in addition to following
-- redirects).
fetchHttp' :: MonadIO m => URI -> Options -> m (Maybe (Response ByteString))
fetchHttp' url opts = liftIO $ fetch `catch` handler
    where fetch = do
            res <- getWith (opts & redirects .~ 10) $ showUri url

            return $ if res ^. responseStatus . statusCode == 200
                     then Just $ toStrict <$> res
                     else Nothing

          handler = const $ return Nothing :: HttpException -> IO (Maybe (Response ByteString))

-- |Convert a URI into a string-like thing.
showUri :: IsString s => URI -> s
showUri uri = fromString $ uriToString id uri ""

-- |Construct a URI
makeUri :: String
        -- ^The domain
        -> String
        -- ^The path
        -> Maybe String
        -- ^The query string
        -> URI
makeUri domain path query = URI { uriScheme    = "http:"
                                , uriAuthority = Just URIAuth { uriUserInfo = ""
                                                              , uriRegName  = domain
                                                              , uriPort     = ""
                                                              }
                                , uriPath      = path
                                , uriQuery     = fromMaybe "" query
                                , uriFragment  = ""
                                }

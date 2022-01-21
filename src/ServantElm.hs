{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# OPTIONS_GHC -Wno-deferred-out-of-scope-variables #-}

module ServantElm
  ( elmForAPI,
  )
where

import Data.Aeson.Types (ToJSON)
import Data.Maybe (catMaybes)
import Data.Text as T (Text, pack, replace, words)
import Data.Text.Encoding (decodeUtf8)
import Data.Text.IO (readFile, writeFile)
import Data.Text.Lazy (fromStrict)
import Elm (prettyShowDecoder)
import Elm.Ast (ElmDefinition (..), ElmPrim (ElmBool, ElmChar, ElmFloat, ElmMaybe), TypeName (TypeName), TypeRef (RefCustom, RefPrim))
import Elm.Generic (Elm (..))
import Elm.TyRep (EType, toElmType)
import Foreign (Int)
import GHC.Desugar (AnnotationWrapper)
import GHC.Generics (Generic, to)
import Lens.Micro ((^.))
import Network.Wai ()
import Network.Wai.Handler.Warp (run)
import Servant (Application, Get, JSON, Proxy (Proxy), Server, serve)
import Servant.API
import Servant.Foreign --as SF (Foreign, GenerateList, HasForeign, HasForeignType (typeFor), PathSegment, Req, Segment, SegmentType (Cap, Static), argName, camelCase, captureArg, listFromAPI, reqFuncName, reqReturnType, unPathSegment, unSegment)
import Text.PrettyPrint.Leijen.Text
  ( Doc,
    comma,
    dquotes,
    encloseSep,
    equals,
    hsep,
    indent,
    lbrace,
    lbracket,
    line,
    parens,
    punctuate,
    rbrace,
    rbracket,
    space,
    text,
    vsep,
    (<$>),
    (<+>),
  )
import Prelude hiding ((<$>))

data LangElm

instance Elm a => HasForeignType LangElm ElmDefinition a where
  typeFor _ _ proxyA = toElmDefinition proxyA

elmForAPI ::
  ( HasForeign LangElm ElmDefinition api,
    GenerateList
      ElmDefinition
      (Foreign ElmDefinition api)
  ) =>
  Proxy api ->
  [Doc]
elmForAPI api =
  map endpointInfoToElmQuery $
    listFromAPI (Proxy :: Proxy LangElm) (Proxy :: Proxy ElmDefinition) api

elmRecord :: [Doc] -> Doc
elmRecord = encloseSep (lbrace <> space) (line <> rbrace) (comma <> space)

indent4Spaces :: Doc -> Doc
indent4Spaces = indent 4

endpointInfoToElmQuery :: Req ElmDefinition -> Doc
endpointInfoToElmQuery requestInfo =
  funcDef
  where
    funcDef =
      vsep
        [ fnName <+> ":" <+> typeSignature,
          fnName <+> args <+> equals,
          indent i elmRequest
        ]

    fnName = error "to implement"
    --request ^. reqFuncName . to (replace . camelCase) . to stext

    --replace = replace "-" "" . replace "." ""

    typeSignature =
      mkTypeSignature requestInfo

    args =
      mkArgs requestInfo

    elmRequest =
      mkRequest requestInfo

elmList :: [Doc] -> Doc
elmList [] = lbracket <> rbracket
elmList ds = lbracket <+> hsep (punctuate (line <> comma) ds) <$> rbracket

stext :: Text -> Doc
stext = text . fromStrict

mkUrl :: [Segment ElmDefinition] -> Doc
mkUrl segments =
  urlBuilder
    <$> (indent i . elmList)
      (map segmentToDoc segments)
  where
    urlBuilder :: Doc
    urlBuilder = "Url.Builder.crossOrigin urlBase" :: Doc -- why "" instead of urlBase in result
    segmentToDoc :: Segment ElmDefinition -> Doc
    segmentToDoc s =
      case unSegment s of
        Static path ->
          dquotes (stext (unPathSegment path))
        Cap arg ->
          error
            "TODO implement" -- for captures, not needed now
            {-let toStringSrc =
                  toString  (maybeOf (arg ^. argType))
             in pipeRight [elmCaptureArg s, toStringSrc]-}

{-elmTypeRefDoc :: TypeRef -> Doc
elmTypeRefDoc = \case
  RefPrim elmPrim -> elmPrimDoc elmPrim
  RefCustom (TypeName typeName) -> pretty typeName
-}

mkTypeSignature :: Req ElmDefinition -> Doc
mkTypeSignature request =
  (hsep . punctuate " ->") ("String" : catMaybes [toMsgType, returnType])
  where
    elmTypeRef :: ElmDefinition -> Doc
    elmTypeRef eDef = error "to-do - copy elmPrimDoc, use elmTypeRefDoc and all dependencies"
    --definitionToRef eDef

    toMsgType :: Maybe Doc
    toMsgType = do
      result <- fmap elmTypeRef $ request ^. reqReturnType
      Just ("(Result Http.Error " <+> parens result <+> " -> msg)")

    returnType :: Maybe Doc
    returnType = do
      pure "Cmd msg"

mkArgs :: Req ElmDefinition -> Doc
mkArgs request =
  hsep ["toMsg"]

mkRequest :: Req ElmDefinition -> Doc
mkRequest request =
  "Http.request"
    <$> indent
      i
      ( elmRecord
          [ "method ="
              <$> indent i (dquotes method),
            "headers ="
              <$> indent i "[]",
            "url ="
              <$> indent i url,
            "body ="
              <$> indent i "Http.emptyBody",
            "expect ="
              <$> indent i expect,
            "timeout ="
              <$> indent i "Nothing",
            "tracker ="
              <$> indent i "Nothing"
          ]
      )
  where
    method = error "to implement"
    --request ^. reqMethod . to (stext . decodeUtf8)

    url =
      mkUrl (request ^. reqUrl . path) -- do I need to understand forall - don't understand the ()
    expect =
      case request ^. reqReturnType of
        Just elmTypeExpr ->
          "Http.expectJson toMsg" {-<+> renderDecoderName elmTypeExpr-}
        Nothing -> error "mkHttpRequest: no reqReturnType?"

{-
renderDecoderName :: EType -> Doc
renderDecoderName elmTypeExpr =
  case elmTypeExpr of
    ETyApp (ETyCon (ETCon "List")) t ->
      parens ("Json.Decode.list " <> parens (renderDecoderName t))
    ETyApp (ETyCon (ETCon "Maybe")) t ->
      parens ("Json.Decode.maybe " <> parens (renderDecoderName t))
    ETyApp x y ->
      parens (renderDecoderName x <+> renderDecoderName y)
    ETyCon (ETCon "Int") -> "Json.Decode.int"
    ETyCon (ETCon "String") -> "Json.Decode.string"
    _ -> ("jsonDec" <> stext (pack (renderElm elmTypeExpr)))
-}

{-renderOnlyDecoderName :: ElmDefinition -> Doc
renderOnlyDecoderName elmTypeExpr = case T.words $ prettyShowDecoder elmTypeExpr of
                                      []   -> emptyDoc
                                      x:_ -> pretty x
-}
{-renderDecoderName :: ElmDefinition -> Doc
renderDecoderName elmTypeExpr =
  case elmTypeExpr of
    DefAlias _ -> renderOnlyDecoderName elmTypeExpr
    DefType _ -> renderOnlyDecoderName elmTypeExpr
    DefPrim (ElmPrim ElmUnit) -> undefined -- error "to-do", don't write it
    DefPrim (ElmNever) -> undefined -- error "to-do"
    DefPrim (ElmBool) -> "Json.Decode.bool"
    DefPrim (ElmChar) -> undefined
    DefPrim (ElmInt) -> "Json.Decode.int"
    DefPrim (ElmFloat) -> "Json.Decode.float"
    DefPrim (ElmString) -> "Json.Decode.string"
    DefPrim (ElmTime) -> undefined
    DefPrim (ElmMaybe a) -> undefined
    DefPrim (ElmResult a a) -> undefined
    DefPrim (ElmPair a a) -> undefined
    DefPrim (ElmTriple a a a) -> undefined
    DefPrim (ElmList a) -> wrapParens
-}

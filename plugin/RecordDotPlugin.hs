{-# OPTIONS_GHC -W #-}

module RecordDotPlugin(plugin) where

import Control.Monad.IO.Class
import Data.Generics.Uniplate.Data
import Control.Arrow(first)
import Control.Monad

import qualified GhcPlugins  as GHC
import           HsExtension (GhcPs, NoExt(..))
import           HsSyn
import           SrcLoc


noL = noLoc
mod_ghc_records = GHC.mkModuleName "GHC.Records"
var_getField = GHC.mkRdrQual mod_ghc_records $ GHC.mkVarOcc "getField"
var_dot = GHC.mkRdrUnqual $ GHC.mkVarOcc "."


plugin :: GHC.Plugin
plugin = GHC.defaultPlugin
    { GHC.parsedResultAction = \_cliOptions -> pluginImpl
    }


pluginImpl :: GHC.ModSummary -> GHC.HsParsedModule -> GHC.Hsc GHC.HsParsedModule
pluginImpl _modSummary m = do
    dflags <- GHC.getDynFlags
    debug $ GHC.showPpr dflags $ GHC.hpm_module m
    -- debug $ SYB.gshow $ GHC.hpm_module m
    let m2 = tweak $ GHC.hpm_module m
    debug $ GHC.showPpr dflags m2
    return m{GHC.hpm_module = m2}


debug :: MonadIO m => String -> m ()
debug = when False . liftIO . putStrLn

tweak :: GHC.Located (HsModule GhcPs) -> GHC.Located (HsModule GhcPs)
tweak = descendBi onExp . descendBi onModule

onModule :: HsModule GhcPs -> HsModule GhcPs
onModule x = x{hsmodImports = magicImport : hsmodImports x}
    where magicImport = noL $ ImportDecl NoExt GHC.NoSourceText (noL mod_ghc_records) Nothing False False True False Nothing Nothing

-- At this point infix expressions have not had associativity/fixity applied, so they are bracketed
-- a + b + c ==> (a + b) + c
-- Therefore we need to deal with, in general:
-- x.y, where
-- x := a | a b | a.b | a + b
-- y := a | a b
onExp :: LHsExpr GhcPs -> LHsExpr GhcPs
onExp (L o (OpApp _ lhs mid rhs))
    | adjacent lhs mid, adjacent mid rhs
    , L _ (HsVar _ (L _ mid)) <- mid, mid == var_dot
    , (lhsOp, lhs) <- getOpRHS $ onExp lhs
    , (lhsApp, lhs) <- getAppRHS lhs
    , (rhsApp, rhs) <- getAppLHS rhs
    , L _ (HsVar _ (L _ rhs)) <- rhs, not $ GHC.isQual rhs
    , let getField = noL $ HsVar NoExt $ noL var_getField
    , let symbol = noL $ HsTyLit NoExt $ HsStrTy GHC.NoSourceText $ GHC.occNameFS $ GHC.rdrNameOcc rhs
    = lhsOp $ rhsApp $ lhsApp $ noL $ HsPar NoExt $ L o $ HsApp NoExt (noL (HsAppType (HsWC NoExt symbol) getField)) lhs
onExp x = descend onExp x


getAppRHS :: LHsExpr GhcPs -> (LHsExpr GhcPs -> LHsExpr GhcPs, LHsExpr GhcPs)
getAppRHS (L l (HsApp p x y)) = (L l . HsApp p x, y)
getAppRHS x = (id, x)

getAppLHS :: LHsExpr GhcPs -> (LHsExpr GhcPs -> LHsExpr GhcPs, LHsExpr GhcPs)
getAppLHS (L l (HsApp p x y)) = first (\c -> L l . (\x -> HsApp p x y) . c) $ getAppLHS x
getAppLHS x = (id, x)

getOpRHS :: LHsExpr GhcPs -> (LHsExpr GhcPs -> LHsExpr GhcPs, LHsExpr GhcPs)
getOpRHS (L l (OpApp p x y z)) = (L l . OpApp p x y, z)
getOpRHS x = (id, x)


adjacent :: Located a -> Located b -> Bool
adjacent (L (RealSrcSpan a) _) (L (RealSrcSpan b) _) =
    srcSpanEndLine a == srcSpanStartLine b &&
    srcSpanEndCol a == srcSpanStartCol b
adjacent _ _ = False

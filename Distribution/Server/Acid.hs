{-# LANGUAGE FlexibleContexts #-}
module Distribution.Server.Acid where

import Control.Monad.Trans (MonadIO(liftIO))
import Data.IORef          (IORef, newIORef, readIORef, writeIORef)
import Data.Acid           hiding (update, query)
import Data.Acid.Advanced  (MethodState, query', update')
import Data.Acid.Local     (createCheckpointAndClose)
import System.FilePath     ((</>))
import System.IO.Unsafe    (unsafePerformIO)

import Distribution.Server.Features.BuildReports.BuildReports (BuildReports)
import Distribution.Server.Features.BuildReports.State        (initialBuildReports)
import Distribution.Server.Packages.Platform        (PlatformPackages, initialPlatformPackages)
-- [reverse index disabled] import Distribution.Server.Packages.Reverse         (ReverseIndex, initialReverseIndex)
import Distribution.Server.Packages.State           (CandidatePackages, Documentation, HackageTrustees, HackageUploaders, PackageMaintainers, PackagesState,
                                                     initialCandidatePackages, initialDocumentation, 
                                                     initialHackageTrustees, initialHackageUploaders,
                                                     initialPackageMaintainers, initialPackagesState)
import Distribution.Server.Users.State              (MirrorClients, initialMirrorClients)

-- WARNING: if you add fields here, you must update checkpointAcid and stopAcid. Failure to do so will *not* result in a compiler error.
data Acid = Acid 
    { acidBuildReports       :: AcidState BuildReports
    , acidCandidatePackages  :: AcidState CandidatePackages
    , acidDocumentation      :: AcidState Documentation
    , acidHackageTrustees    :: AcidState HackageTrustees
    , acidHackageUploaders   :: AcidState HackageUploaders
    , acidMirrorClients      :: AcidState MirrorClients
    , acidPackageMaintainers :: AcidState PackageMaintainers
    , acidPackagesState      :: AcidState PackagesState
    , acidPlatformPackages   :: AcidState PlatformPackages
    -- [reverse index disabled] , acidReverseIndex       :: AcidState ReverseIndex
    }

class AcidComponent c where
    acidComponent :: Acid -> AcidState c

instance AcidComponent BuildReports where
    acidComponent = acidBuildReports

instance AcidComponent CandidatePackages where
    acidComponent = acidCandidatePackages

instance AcidComponent Documentation where
    acidComponent = acidDocumentation

instance AcidComponent HackageTrustees where
    acidComponent = acidHackageTrustees

instance AcidComponent HackageUploaders where
    acidComponent = acidHackageUploaders

instance AcidComponent MirrorClients where
    acidComponent = acidMirrorClients

instance AcidComponent PackageMaintainers where
    acidComponent = acidPackageMaintainers

instance AcidComponent PackagesState where
    acidComponent = acidPackagesState

instance AcidComponent PlatformPackages where
    acidComponent = acidPlatformPackages

-- [reverse index disabled] instance AcidComponent ReverseIndex where
-- [reverse index disabled]     acidComponent = acidReverseIndex


acidRef :: IORef Acid
acidRef = unsafePerformIO $ newIORef (error "acid not initialized.")
{-# NOINLINE acidRef #-}

-- FIXME: a strictly temporary measure, while we're converting to encapsulated state use
unsafeGetAcid :: AcidComponent c => AcidState c
unsafeGetAcid = unsafePerformIO $ do
  acid <- liftIO $ readIORef acidRef
  return (acidComponent acid)

setAcid :: Acid -> IO ()
setAcid acid =
    writeIORef acidRef acid

startAcid :: FilePath -> IO Acid
startAcid stateDir =
    startAcid' stateDir 
           initialBuildReports
           initialCandidatePackages
           initialDocumentation
           initialHackageTrustees
           initialHackageUploaders
           initialMirrorClients
           initialPackageMaintainers
           initialPackagesState
           initialPlatformPackages
           -- [reverse index disabled] initialReverseIndex

startAcid' :: FilePath 
           -> BuildReports
           -> CandidatePackages
           -> Documentation
           -> HackageTrustees
           -> HackageUploaders
           -> MirrorClients
           -> PackageMaintainers
           -> PackagesState
           -> PlatformPackages
           -- [reverse index disabled] -> ReverseIndex
           -> IO Acid
startAcid' stateDir buildReports candidatePackages documentation hackageTrustees hackageUploaders mirrorClients packageMaintainers packagesState platformPackages
    -- [reverse index disabled] reverseIndex
    =
    do buildReports'       <- openLocalStateFrom (stateDir </> "BuildReports")       buildReports
       candidatePackages'  <- openLocalStateFrom (stateDir </> "CandidatePackages")  candidatePackages
       documentation'      <- openLocalStateFrom (stateDir </> "Documentation")      documentation
       hackageTrustees'    <- openLocalStateFrom (stateDir </> "HackageTrustees")    hackageTrustees
       hackageUploaders'   <- openLocalStateFrom (stateDir </> "HackageUploaders")   hackageUploaders
       mirrorClients'      <- openLocalStateFrom (stateDir </> "MirrorClients")      mirrorClients
       packageMaintainers' <- openLocalStateFrom (stateDir </> "PackageMaintainers") packageMaintainers
       packagesState'      <- openLocalStateFrom (stateDir </> "PackagesState")      packagesState
       platformPackages'   <- openLocalStateFrom (stateDir </> "PlatformPackages")   platformPackages
       -- [reverse index disabled] reverseIndex'       <- openLocalStateFrom (stateDir </> "ReverseIndex")       reverseIndex
       let acid = Acid { acidBuildReports       = buildReports' 
                       , acidCandidatePackages  = candidatePackages'
                       , acidDocumentation      = documentation'
                       , acidHackageTrustees    = hackageTrustees'
                       , acidHackageUploaders   = hackageUploaders'
                       , acidMirrorClients      = mirrorClients'
                       , acidPackageMaintainers = packageMaintainers'
                       , acidPackagesState      = packagesState'
                       , acidPlatformPackages   = platformPackages'
                       -- [reverse index disabled] , acidReverseIndex       = reverseIndex'
                       }
       setAcid acid
       return acid

stopAcid :: Acid -> IO ()
stopAcid acid = 
    do setAcid (error "acid-state has been shutdown already.")
       createCheckpointAndClose (acidBuildReports acid)
       createCheckpointAndClose (acidCandidatePackages acid)
       createCheckpointAndClose (acidDocumentation acid)
       createCheckpointAndClose (acidHackageTrustees acid)
       createCheckpointAndClose (acidHackageUploaders acid)
       createCheckpointAndClose (acidMirrorClients acid)
       createCheckpointAndClose (acidPackageMaintainers acid)
       createCheckpointAndClose (acidPackagesState acid)
       createCheckpointAndClose (acidPlatformPackages acid)
       -- [reverse index disabled] createCheckpointAndClose (acidReverseIndex acid)

checkpointAcid :: Acid -> IO ()
checkpointAcid acid =
    do createCheckpoint (acidBuildReports acid)
       createCheckpoint (acidCandidatePackages acid)
       createCheckpoint (acidDocumentation acid)
       createCheckpoint (acidHackageTrustees acid)
       createCheckpoint (acidHackageUploaders acid)
       createCheckpoint (acidMirrorClients acid)
       createCheckpoint (acidPackageMaintainers acid)
       createCheckpoint (acidPackagesState acid)
       createCheckpoint (acidPlatformPackages acid)
       -- [reverse index disabled] createCheckpoint (acidReverseIndex acid)

update :: ( AcidComponent (MethodState event)
          , UpdateEvent event
          , MonadIO m) => event -> m (EventResult event)
update ev = 
    do acid <- liftIO $ readIORef acidRef
       update' (acidComponent acid) ev

query :: ( AcidComponent (MethodState event)
          , QueryEvent event
          , MonadIO m) => event -> m (EventResult event)
query ev = 
    do acid <- liftIO $ readIORef acidRef
       query' (acidComponent acid) ev


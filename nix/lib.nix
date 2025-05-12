{ pkgs }:
let
  addNativeBuildInputs =
    drvs:
    (old: {
      nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ drvs;
    });
  addBuildInputs =
    drvs:
    old: {
      buildInputs = (old.buildInputs or []) ++ drvs;
    };
  addResolved =
    final: names:
    (old: {
      nativeBuildInputs =
        (old.nativeBuildInputs or [ ])
        ++ final.resolveBuildSystem (
          pkgs.lib.listToAttrs (map (name: pkgs.lib.nameValuePair name [ ]) names)
        );
    });
in {
  inherit addNativeBuildInputs addBuildInputs addResolved;
}

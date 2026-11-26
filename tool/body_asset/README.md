# body.glb

`packages/body_mapping/lib/assets/body.glb` is built from CC0 MakeHuman assets
(base mesh, macro targets, measurement targets, skin weights):

```sh
tool/body_asset/fetch_makehuman.sh .makehuman
python3 tool/body_asset/build_body.py .makehuman packages/body_mapping/lib/assets/body.glb   # needs numpy
```

Any change to the file must bump `BodyAsset.version`, update the hash in
`packages/body_mapping/test/src/body_asset_test.dart`, and regenerate the golden
numbers (`UPDATE_GOLDENS=1 dart test` in `packages/body_mapping`).
Still to do (LLD build step 2): pin the MakeHuman commit, trunk sub-masks,
a low-poly variant, and a CI job that rebuilds the file and checks the hash.

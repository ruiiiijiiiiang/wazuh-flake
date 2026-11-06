{
  version = "4.14.10";

  hashes = {
    common = {
      filebeatModule = "7a8c67c47b22f89ab271b7e35f108f18b2215b7aa411cdd23c9994393070d38d";
      filebeatTemplate = "b2d182f49cc68957849e77fd2d79528fd2273ebaec1106c9661c9e320577a089";
    };
    amd64 = {
      agent = "873cfec3720a7d7a344afc2c646cf5895a04caa3e4dd7b5124987264f711db94";
      manager = "306babec56d241cb5b77bbc97d1aa4546d267e0a00ad8f89c773dacd70ef5686";
      indexer = "7bb918b38891b69425a0a90a9239a4574264837224a3c6ae84b5c5ef419a8dbe";
      dashboard = "b90519a38437fe66123422ef61068ab539988267d351b52c0262d123f0e8636f";
      filebeat = "f759a13e5407bba184d9f0235ab88409a0d77d821e64adb3dcc0ba8e397f0201";
    };
    arm64 = {
      agent = "641e5f30cfa8714e387cf6efcce00d91c0f152dcabc34e868a813b55f6a6aedf";
      manager = "960365f73d4bbf02df66baa3e3a4aa71517274cc69bbc333a1b018c4ecd63c20";
      indexer = "86192d1a8beb7fc2d7b26844f29251b47c1f0b69dfdc68fbec262a7e2851b914";
      dashboard = "9cf5642e2eb8fc06aef1dc3f373dec46775e0ecad08a0cd26db802795d84345b";
      filebeat = "93860759c538813cfe34f88a4e4047fba45fead287a7d11fea8957c1d816cfd9";
    };
  };
}

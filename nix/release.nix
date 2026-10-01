{
  version = "4.14.8";

  hashes = {
    common = {
      filebeatModule = "7a8c67c47b22f89ab271b7e35f108f18b2215b7aa411cdd23c9994393070d38d";
      filebeatTemplate = "b2d182f49cc68957849e77fd2d79528fd2273ebaec1106c9661c9e320577a089";
    };
    amd64 = {
      agent = "6ed202e211fd8c544d1906c9b94dcd4b503d1829eef7d0a82ce4bcf4a1688967";
      manager = "adeecbcaf143a342f2232e72795c430d25c049dcfaf66550b35326e799c9ee83";
      indexer = "639624f8ac4f83d4cb5951491a1813ccc1aea6b0ed0e4b5c0590f6cacf8e250f";
      dashboard = "f2413085b21295e681cca0bd6e2a360174417d241bafbeab5fe7685e2d86f2d4";
      filebeat = "f759a13e5407bba184d9f0235ab88409a0d77d821e64adb3dcc0ba8e397f0201";
    };
    arm64 = {
      agent = "33028279fde10e008ed92dd228c2b42ab5aa84f28705f80b76ce867b48e48bad";
      manager = "261a909ac1c579beee811d2c945a8bb92f1b052a9b4f85a98a1c56f8cc995207";
      indexer = "4f7383503c26791024a8b1650a81c0db8b9430e9b0fc3cfc53cdb4387cf6c943";
      dashboard = "bc13b919d48499c347f98daf916f2890d30f898a697c06b7530db25d61187a2c";
      filebeat = "93860759c538813cfe34f88a4e4047fba45fead287a7d11fea8957c1d816cfd9";
    };
  };
}

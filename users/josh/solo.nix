{lib, ...}: {
  programs.git = {
    userName = lib.mkForce "Josh Perry";
    userEmail = lib.mkForce "j.perry@gosolo.io";
    signing = lib.mkForce {
      key = null;
      signByDefault = false;
    };
  };
}

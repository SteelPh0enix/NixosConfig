# libmediainfo 26.10 stopped detecting the 26 ms ID3v2-tagged MP3 that pymediainfo's cover-data
# test parses, so that one test fails while the other 57 pass (MediaArea/MediaInfoLib#2736, no fix
# upstream). Skip it, keep the rest.
_final: prev: {
  python3Packages = prev.python3Packages.overrideScope (
    _pyFinal: pyPrev: {
      pymediainfo = pyPrev.pymediainfo.overrideAttrs {
        installCheckPhase = ''
          py.test -k 'not test_parse_url and not test_parse_cover_data' tests
        '';
      };
    }
  );
}

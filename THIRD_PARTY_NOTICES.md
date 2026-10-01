# Third-party notices

`Source/reader.html` contains the bundled JSZip 3.10.1 distribution so `.pptx` and image-ZIP imports can run without a CDN. JSZip offers MIT or GPLv3; this project uses the **MIT option**. Its unmodified notice file is in `Licenses/JSZip-LICENSE.md` and notices also appear inside the HTML.

The bundle includes dependency notices for core-util-is, immediate, inherits, lie, pako, process-nextick-args, readable-stream, safe-buffer, setimmediate, string_decoder and util-deprecate. Preserve every included notice in `Licenses/` when redistributing this bundle; the root MIT license does not replace those terms.

The native app uses system Apple frameworks and the separately installed Microsoft PowerPoint application. Neither is distributed in this repository. Playwright is a development/test dependency installed separately; its browser downloads and their licenses are not bundled here. No font files are distributed.

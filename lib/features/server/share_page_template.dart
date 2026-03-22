String buildSharePageHtml({
  required String fileName,
  required String mimeType,
  required String fileSize,
  String? senderAlias,
  String? sharedText,
  String? webLinkUrl,
  bool showImagePreview = false,
  bool showVideoPreview = false,
}) {
  final subtitleText = (senderAlias != null && senderAlias.trim().isNotEmpty)
      ? '$senderAlias shared this file with you.'
      : 'A nearby device shared this file with you.';

  final textToolsSection = sharedText == null
      ? ''
      : '''
      <div class="text-tools">
        <div class="label">Text content</div>
        <textarea id="sharedText" readonly>$sharedText</textarea>
        <button type="button" class="copy" onclick="copySharedText()">Copy text</button>
        <p class="status" id="copyStatus"></p>
      </div>
''';

  final textToolsScript = sharedText == null
      ? ''
      : '''
  <script>
    async function copySharedText() {
      const textArea = document.getElementById('sharedText');
      const status = document.getElementById('copyStatus');
      const text = textArea ? textArea.value : '';
      if (!text) return;
      try {
        if (navigator.clipboard && navigator.clipboard.writeText) {
          await navigator.clipboard.writeText(text);
        } else {
          textArea.focus();
          textArea.select();
          document.execCommand('copy');
        }
        status.textContent = 'Copied text to clipboard.';
      } catch (_) {
        status.textContent = 'Copy failed. Please select and copy manually.';
      }
    }
  </script>
''';

  final previewSection = webLinkUrl != null
      ? '''
      <div class="preview">
        <div class="label">Web link preview</div>
        <a class="link-preview" href="$webLinkUrl" target="_blank" rel="noopener noreferrer">$webLinkUrl</a>
      </div>
'''
      : showImagePreview
          ? '''
      <div class="preview">
        <div class="label">Photo preview</div>
        <img class="media-preview" src="/share/download" alt="Shared image preview" />
      </div>
'''
          : showVideoPreview
              ? '''
      <div class="preview">
        <div class="label">Video preview</div>
        <video class="media-preview" controls preload="metadata" src="/share/download"></video>
      </div>
'''
              : '';

  return '''
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>UniDrop Share</title>
  <style>
    :root {
      color-scheme: light;
    }

    * {
      box-sizing: border-box;
    }

    body {
      margin: 0;
      min-height: 100vh;
      display: grid;
      place-items: center;
      padding: 20px;
      font-family: Inter, Segoe UI, Roboto, Helvetica, Arial, sans-serif;
      background: radial-gradient(circle at top, #f2f7ff 0%, #e9eef9 45%, #dde6f7 100%);
      color: #0f172a;
    }

    .card {
      width: min(100%, 520px);
      border-radius: 20px;
      background: rgba(255, 255, 255, 0.95);
      border: 1px solid #dbe5f5;
      box-shadow: 0 14px 35px rgba(15, 23, 42, 0.12);
      overflow: hidden;
    }

    .header {
      padding: 20px 22px 14px;
      background: linear-gradient(120deg, #2563eb 0%, #4f46e5 100%);
      color: #fff;
    }

    .title {
      margin: 0;
      font-size: 1.25rem;
      font-weight: 700;
      letter-spacing: 0.2px;
    }

    .subtitle {
      margin: 8px 0 0;
      font-size: 0.92rem;
      opacity: 0.9;
    }

    .content {
      padding: 18px 22px 22px;
    }

    .meta {
      display: grid;
      grid-template-columns: 88px 1fr;
      row-gap: 10px;
      column-gap: 10px;
      align-items: start;
      margin-bottom: 18px;
      font-size: 0.95rem;
    }

    .label {
      color: #475569;
      font-weight: 600;
    }

    .value {
      color: #0f172a;
      word-break: break-word;
    }

    .download {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      min-height: 44px;
      padding: 0 18px;
      border-radius: 12px;
      text-decoration: none;
      background: linear-gradient(120deg, #2563eb 0%, #4f46e5 100%);
      color: #fff;
      font-weight: 600;
      transition: transform .15s ease, box-shadow .15s ease, opacity .15s ease;
      box-shadow: 0 8px 18px rgba(37, 99, 235, 0.25);
    }

    .download:hover {
      transform: translateY(-1px);
      box-shadow: 0 10px 24px rgba(37, 99, 235, 0.32);
    }

    .download:active {
      transform: translateY(0);
      opacity: .95;
    }

    .note {
      margin-top: 14px;
      color: #64748b;
      font-size: 0.84rem;
    }

    .text-tools {
      margin-top: 16px;
      border-top: 1px solid #e2e8f0;
      padding-top: 14px;
    }

    textarea {
      width: 100%;
      min-height: 112px;
      margin-top: 8px;
      padding: 10px;
      border: 1px solid #cbd5e1;
      border-radius: 10px;
      font: inherit;
      color: #0f172a;
      background: #f8fafc;
      resize: vertical;
      line-height: 1.4;
    }

    .copy {
      margin-top: 10px;
      border: none;
      min-height: 40px;
      padding: 0 14px;
      border-radius: 10px;
      color: #fff;
      font-weight: 600;
      background: #0f172a;
      cursor: pointer;
    }

    .status {
      margin: 8px 0 0;
      color: #475569;
      font-size: 0.84rem;
      min-height: 1.2em;
    }

    .preview {
      margin-top: 16px;
      border-top: 1px solid #e2e8f0;
      padding-top: 14px;
    }

    .media-preview {
      margin-top: 8px;
      width: 100%;
      max-height: 320px;
      object-fit: contain;
      border: 1px solid #cbd5e1;
      border-radius: 10px;
      background: #0b1220;
    }

    .link-preview {
      display: inline-block;
      margin-top: 8px;
      color: #1d4ed8;
      word-break: break-all;
      text-decoration: none;
      font-weight: 600;
    }

    .link-preview:hover {
      text-decoration: underline;
    }

    @media (max-width: 480px) {
      .meta {
        grid-template-columns: 1fr;
      }

      .label {
        margin-top: 6px;
      }
    }
  </style>
</head>
<body>
  <main class="card">
    <section class="header">
      <h1 class="title">UniDrop File Share</h1>
      <p class="subtitle">$subtitleText</p>
    </section>
    <section class="content">
      <div class="meta">
        <div class="label">File</div>
        <div class="value">$fileName</div>
        <div class="label">Type</div>
        <div class="value">$mimeType</div>
        <div class="label">Size</div>
        <div class="value">$fileSize</div>
      </div>
      <a class="download" href="/share/download">Download file</a>
      $previewSection
      $textToolsSection
      <p class="note">If download does not start, keep this page open and try again.</p>
    </section>
  </main>
  $textToolsScript
</body>
</html>
''';
}

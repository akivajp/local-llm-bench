# Claude Code 接続確認用の課題

`scripts/phase4.sh` が各課題を作業ディレクトリに複製し、ローカル LLM をバックエンドにした
Claude Code (`claude -p --bare`) に `prompt.txt` を渡して解かせる。終了後に `python3 -m pytest -q` を実行して成否を判定する。

- t1-fizzbuzz: 新規にファイルを作り、テストも書いて通す
- t2-bugfix: 既存コードの2箇所のバグ (mean の分母、偶数個の median の添字) を、テストを変えずに直す

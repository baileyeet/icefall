#!/usr/bin/env python3
# Copyright    2023  Xiaomi Corp.        (authors: Zengrui Jin)
#
# See ../../../../LICENSE for clarification regarding multiple authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# This script tokenizes the training transcript by CJK characters
# and saves the result to transcript_chars.txt, which is used
# to train the BPE model later.

import argparse
from pathlib import Path

from tqdm.auto import tqdm


def tokenize_by_ja_char(line: str) -> str:
    """
    Tokenize a line of text with Japanese characters.

    Note: All non-Japanese characters will be upper case.

    Example:
      input = "こんにちは世界は hello world の日本語"
      output = "こ ん に ち は 世 界 は HELLO WORLD の 日 本 語"

    Args:
      line:
        The input text.

    Return:
      A new string tokenized by Japanese characters.
    """
    pattern = re.compile(r"([\u3040-\u309F\u30A0-\u30FF\u4E00-\u9FFF])")
    chars = pattern.split(line.strip())
    return " ".join(
        [w.strip().upper() if not pattern.match(w) else w for w in chars if w.strip()]
    )


def get_args():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--lang-dir",
        type=str,
        help="""Output directory.
        The generated transcript_chars.txt is saved to this directory.
        """,
    )

    parser.add_argument(
        "--text",
        type=str,
        help="Training transcript.",
    )

    return parser.parse_args()


def main():
    args = get_args()
    lang_dir = Path(args.lang_dir)
    text = Path(args.text)

    assert lang_dir.exists() and text.exists(), f"{lang_dir} or {text} does not exist!"

    transcript_path = lang_dir / "transcript_chars.txt"

    with open(text, "r", encoding="utf-8") as fin:
        with open(transcript_path, "w+", encoding="utf-8") as fout:
            for line in tqdm(fin):
                fout.write(tokenize_by_ja_char(line) + "\n")


if __name__ == "__main__":
    main()

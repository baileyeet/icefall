#!/usr/bin/env bash

# fix segmentation fault reported in https://github.com/k2-fsa/icefall/issues/674
export PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION=python

set -eou pipefail

stage=-1
stop_stage=100

dl_dir=$PWD/download

. shared/parse_options.sh || exit 1

vocab_sizes=(
  2000
)

# All files generated by this script are saved in "data".
# You can safely remove "data" and rerun this script to regenerate it.
mkdir -p data

log() {
  # This function is from espnet
  local fname=${BASH_SOURCE[1]##*/}
  echo -e "$(date '+%Y-%m-%d %H:%M:%S') (${fname}:${BASH_LINENO[0]}:${FUNCNAME[1]}) $*"
}

log "dl_dir: $dl_dir"

log "Dataset: musan"
if [ $stage -le 1 ] && [ $stop_stage -ge 1 ]; then
  log "Stage 1: Soft link fbank of musan"
  mkdir -p data/fbank
  if [ -e ../../librispeech/ASR/data/fbank/.musan.done ]; then
    cd data/fbank
    ln -svf $(realpath ../../../../librispeech/ASR/data/fbank/musan_feats) .
    ln -svf $(realpath ../../../../librispeech/ASR/data/fbank/musan_cuts.jsonl.gz) .
    cd ../..
  else
    log "Abort! Please run ../../librispeech/ASR/prepare.sh --stage 4 --stop-stage 4"
    exit 1
  fi
fi

log "Dataset: LibriSpeech"
if [ $stage -le 2 ] && [ $stop_stage -ge 2 ]; then
  log "Stage 1: Soft link fbank of LibriSpeech"
  mkdir -p data/fbank
  if [ -e ../../librispeech/ASR/data/fbank/.librispeech.done ]; then
    cd data/fbank
    ln -svf $(realpath ../../../../librispeech/ASR/data/fbank/librispeech_cuts*) .
    ln -svf $(realpath ../../../../librispeech/ASR/data/fbank/librispeech_feats*) .
    cd ../..
  else
    log "Abort! Please run ../../librispeech/ASR/prepare.sh --stage 1 --stop-stage 1 and ../../librispeech/ASR/prepare.sh --stage 3 --stop-stage 3"
    exit 1
  fi
fi

log "Dataset: ReazonSpeech"
if [ $stage -le 3 ] && [ $stop_stage -ge 3 ]; then
  log "Stage 2: Soft link fbank of ReazonSpeech"
  mkdir -p data/fbank
  if [ -e ../../reazonspeech/ASR/data/manifests/.reazonspeech.done ]; then
    cd data/fbank
    ln -svf $(realpath ../../../../reazonspeech/ASR/data/manifests/reazonspeech_cuts*) .
    cd ..
    mkdir -p manifests
    cd manifests
    ln -svf $(realpath ../../../../reazonspeech/ASR/data/manifests/feats_train) .
    ln -svf $(realpath ../../../../reazonspeech/ASR/data/manifests/feats_dev) .
    ln -svf $(realpath ../../../../reazonspeech/ASR/data/manifests/feats_test) .
    cd ../..
  else
    log "Abort! Please run ./prepare.sh --stage 2 --stop-stage 2"
    exit 1
  fi
fi

# New Stage 3: Prepare char based lang for ReazonSpeech
if [ $stage -le 3 ] && [ $stop_stage -ge 3 ]; then
  lang_char_dir=data/lang_char
  log "Stage 3: Prepare char based lang for ReazonSpeech"
  mkdir -p $lang_char_dir

  # Prepare text
  if [ ! -f $lang_char_dir/text ]; then
    gunzip -c ../../reazonspeech/ASR/data/manifests/reazonspeech_supervisions_train.jsonl.gz \
      | jq '.text' | sed 's/"//g' \
      | ./local/text2token.py -t "char" > $lang_char_dir/text
  fi

  # jp word segmentation for text
  if [ ! -f $lang_char_dir/text_words_segmentation ]; then
    python3 ./local/text2segments.py \
      --input-file $lang_char_dir/text \
      --output-file $lang_char_dir/text_words_segmentation
  fi

  cat $lang_char_dir/text_words_segmentation | sed 's/ /\n/g' \
    | sort -u | sed '/^$/d' | uniq > $lang_char_dir/words_no_ids.txt

  if [ ! -f $lang_char_dir/words.txt ]; then
    python3 ./local/prepare_words.py \
      --input-file $lang_char_dir/words_no_ids.txt \
      --output-file $lang_char_dir/words.txt
  fi

  if [ ! -f $lang_char_dir/L_disambig.pt ]; then
    python3 ./local/prepare_char.py
  fi
fi

if [ $stage -le 4 ] && [ $stop_stage -ge 4 ]; then
  log "Stage 4: Prepare Byte BPE based lang"
  mkdir -p data/fbank
  if [ ! -d ../../reazonspeech/ASR/data/lang_char ] && [ ! -d ./data/lang_char ]; then
    log "Abort! Please run ../../reazonspeech/ASR/prepare.sh --stage 3 --stop-stage 3"
    exit 1
  fi

  if [ ! -d ../../librispeech/ASR/data/lang_bpe_500 ] && [ ! -d ./data/lang_bpe_500 ]; then
    log "Abort! Please run ../../librispeech/ASR/prepare.sh --stage 5 --stop-stage 5"
    exit 1
  fi

  cd data/
  # if [ ! -d ./lang_char ]; then
  #   ln -svf $(realpath ../../../reazonspeech/ASR/data/lang_char) .
  # fi
  if [ ! -d ./lang_bpe_500 ]; then
    ln -svf $(realpath ../../../librispeech/ASR/data/lang_bpe_500) .
  fi
  cd ../

  for vocab_size in ${vocab_sizes[@]}; do
    lang_dir=data/lang_bbpe_${vocab_size}
    mkdir -p $lang_dir

    cat data/lang_char/text data/lang_bpe_500/transcript_words.txt \
      > $lang_dir/text

    if [ ! -f $lang_dir/transcript_chars.txt ]; then
      ./local/prepare_for_bpe_model.py \
        --lang-dir ./$lang_dir \
        --text $lang_dir/text
    fi

    if [ ! -f $lang_dir/text_words_segmentation ]; then
      python3 ./local/text2segments.py \
        --input-file ./data/lang_char/text \
        --output-file $lang_dir/text_words_segmentation

      cat ./data/lang_bpe_500/transcript_words.txt \
        >> $lang_dir/text_words_segmentation
    fi

    cat $lang_dir/text_words_segmentation | sed 's/ /\n/g' \
      | sort -u | sed '/^$/d' | uniq > $lang_dir/words_no_ids.txt

    if [ ! -f $lang_dir/words.txt ]; then
      python3 ./local/prepare_words.py \
        --input-file $lang_dir/words_no_ids.txt \
        --output-file $lang_dir/words.txt
    fi

    if [ ! -f $lang_dir/bbpe.model ]; then
      ./local/train_bbpe_model.py \
        --lang-dir $lang_dir \
        --vocab-size $vocab_size \
        --transcript $lang_dir/text
    fi

    if [ ! -f $lang_dir/L_disambig.pt ]; then
      ./local/prepare_lang_bbpe.py --lang-dir $lang_dir

      log "Validating $lang_dir/lexicon.txt"
      ln -svf $(realpath ../../multi_zh_en/ASR/local/validate_bpe_lexicon.py) local/
      ./local/validate_bpe_lexicon.py \
        --lexicon $lang_dir/lexicon.txt \
        --bpe-model $lang_dir/bbpe.model
    fi
  done
fi

log "prepare_einishi.sh: PREPARATION DONE"

#!/usr/bin/perl -w
use strict;
use utf8;
use Cwd qw (getcwd);

# E-Hentai, EX-Hentai, Lo-Fi からのダウンローダー．
# -h で簡単なヘルプ表示，同梱のreadme.txt に詳細があります．
# シェバン行と基本設定部分を書き換えてお使いください．
# 改変，再配布はご自由に（NYSL Version 0.9982）．

#----------------------------------------------------------------------
# 基本設定
#----------------------------------------------------------------------
### ファイルシステムの文字コード
# Windows: cp932
# Linux: utf8
#my $FSCharset = "cp932";
my $FSCharset = "utf8";

### デフォルトの保存ディレクトリの基準となるパス
# ディレクトリの区切りは '/' または '\\'．末尾には任意．
# -D オプションで変更可.
my $defaultBaseDir = './download/';

### ダウンロード後のファイルの命名規則
# 1: 元ファイル名
# 2: 連番
# 3: 連番_元ファイル名
my $namingRule = 3;

### キューリスト処理失敗時にレジューム用ログを記録するか
# 0: しない
# 1: する
my $resumeLogFlag = 1;

### キューリスト処理失敗時のレジューム用ログを記録するファイル
# 下記の設定ではカレントディレクトリのresume_年月日時分秒.txtに記録する
# -r オプションで変更可
my $defaultResumeLogFile 
  = "./resume_".EHG::Util::getFormattedLocalTime().".txt";

#----------------------------------------------------------------------
# 詳細設定（主要な動作に影響はありません）
#----------------------------------------------------------------------
### 進行状況/デバッグ用メッセージの表示レベル
# 0: ナシ
# 1: 標準
# 2: 詳細
my $debugLebel = 1;

### HTTP リクエスト毎の待ち時間（秒）
my $sleepSec = 2;

### HTTP リクエストに失敗したときの待ち時間（秒）
my $sleepFailedSec = 10;

### HTTP リクエストのタイムアウト（秒）
my $timeOutSec = 20;

### HTTP リクエストの最大試行回数
# この数だけリクエストに失敗すれば，アクセス制限を受けていると判断
my $maxHTTPTrial = 2;

### プロキシを変更する最大の回数
# プロキシリストが与えられている時にアクセス制限を受けた場合，
# 最大この値とプロキシリスト数のうち，小さい数だけプロキシを変更する
my $maxProxyTrial = 2;

### プロキシリスト
# これに -P オプションで与えられたファイルからもプロキシが追加される
# 先頭の http:// は任意．
# 例: my @proxies = qw(localhost:8080 http://192.168.0.1:80);
my @defaultProxyList = qw();

### Proxy リストからの Proxy の選び方
# 1: 上から順に
# 2: ランダム
my $proxyListOrder = 2;

### ダウンロードを試みる最大のページ数
my $maxPageNum = 2000;

### WWW::Mechanize が自称するユーザーエージェント
my $agentAlias = 'Windows Mozilla';

#----------------------------------------------------------------------
# 起動時の情報を格納する変数
#----------------------------------------------------------------------
# 起動時のカレントディレクトリ
my $orgCurrentDir = getcwd();

#----------------------------------------------------------------------
# メインルーチン
#----------------------------------------------------------------------
{
  package EHG;
  use strict;
  use utf8;
  use File::Spec;
  
  # 文字コードを設定
  setFSCharset();
  EHG::Util::printMsg("Start ehgm.pl.",2);
  
  # コマンドライン引数を処理
  my ($helpFlag, $queueListFile, $targetURL, $thumbURL, 
      $firstPageNum, $lastPageNum, $saveDir, $baseDir, 
      $proxy, $proxyListFile, $resumeLogFile)
    = getArgs(@ARGV);
  
  if($helpFlag){ # -h オプションが与えられていれば，ヘルプを表示して終了
    showHelp();
  }elsif($queueListFile){ # キューリストファイルに基づいて処理を行う
    execQueueList($queueListFile, $saveDir, $baseDir,
                  $proxy, $proxyListFile, $resumeLogFile);
  }elsif($targetURL){ # 直接キューを処理する
    my $queue = EHG::Queue->new(
      targetURL     => $targetURL,    thumbURL      => $thumbURL,
      firstPageNum  => $firstPageNum, lastPageNum   => $lastPageNum, 
      saveDir       => $saveDir,      baseDir       => $baseDir, 
      proxy         => $proxy,        proxyListFile => $proxyListFile);
    $queue->run();
  }else{ # メッセージを表示
    EHG::Util::printMsg("URL or queue list file must be specified.", 1);
    EHG::Util::printMsg("Type ehgm.pl -h for help.", 1);
  }
  
  # 終了
  EHG::Util::printMsg("End ehgm.pl.", 2);
  exit 0;

  #---------------------------------------------------------------------
  # プログラム全体の制御に関するサブルーチン
  #---------------------------------------------------------------------
  ### コマンドライン引数の処理
  sub getArgs{
    EHG::Util::printMsg("EHG::getArgs called.", 2);
    my @args = map{EHG::Util::decodeFSC($_)}@_; # 外部入力の引数をデコード
    my $helpFlag      = undef;
    my $targetURL     = undef;
    my $thumbURL      = undef;
    my $queueListFile = undef;
    my $firstPageNum  = 1;
    my $lastPageNum   = $maxPageNum;
    my $saveDir       = undef; # 非設定時には$baseDir/タイトル名 に保存
    my $baseDir       = $defaultBaseDir;
    my $proxy         = $ENV{HTTP_PROXY} || undef;
    my $proxyListFile = undef;
    my $resumeLogFile = $defaultResumeLogFile || undef;
  
    my $n = 0;
    while($n<=$#args){
      # オプション名指定付き
      if(    $args[$n] eq '-d'){                  # 保存ディレクトリ
        $saveDir        = $args[++$n];
      }elsif($args[$n] eq '-D'){                  # 基準ディレクトリ
        $baseDir        = $args[++$n];
      }elsif($args[$n] eq '-f'){                  # 開始ページ数
        $firstPageNum  = $args[++$n];
      }elsif($args[$n] eq '-h'){                  # ヘルプ
        $helpFlag      = 1;
      }elsif($args[$n] eq '-l'){                  # 終了ページ数
        $lastPageNum   = $args[++$n];
      }elsif($args[$n] eq '-p'){                  # プロキシ
        $proxy         = $args[++$n];
      }elsif($args[$n] eq '-P'){                  # プロキシリスト
        $proxyListFile = $args[++$n];
      }elsif($args[$n] eq '-q'){                  # キューリスト
        $queueListFile = $args[++$n];
      }elsif($args[$n] eq '-r'){                  # レジュームファイル
        $resumeLogFile = $args[++$n];
      }elsif($args[$n] eq '-t'){                  # サムネイルURL
        $thumbURL = EHG::URL->new($args[++$n]);
      # オプション名指定なし
      }elsif($args[$n] =~ /^http/){               # Index/開始URL
        $targetURL = EHG::URL->new($args[$n]);
      }elsif(-f $args[$n] && $args[$n] !~ /^-/){  # キューリスト
        $queueListFile = $args[$n];
      }elsif($args[$n] !~ /^-/){                  # 保存ディレクトリ
        $saveDir        = $args[$n];              # 最後に処理
      }else{
        EHG::Util::printMsg("Can't recognize option '".$args[$n]."'", 1);
      }
      $n++;
    }
    
    # フォーマットの調整
    $proxy   =~s{^(http://)?}{http://} if $proxy;
    $baseDir =~s{[/\\]?$}{/};
    $saveDir =~s{[/\\]?$}{/} if $saveDir;
    $saveDir       = File::Spec->rel2abs($saveDir) if $saveDir;
    $resumeLogFile = File::Spec->rel2abs($resumeLogFile) if $resumeLogFile;
    
    return ($helpFlag, $queueListFile, $targetURL, $thumbURL,
            $firstPageNum, $lastPageNum, $saveDir, $baseDir,
            $proxy, $proxyListFile, $resumeLogFile);
  }

  ### ヘルプを表示する
  sub showHelp{
    print<<_HELP_

  ehgm.pl - Downloader from E-Hentai, EX-Hentai, and Lo-Fi -
  ==========================================================

usage: ehgm.pl URL | FILE [DIRECTORY] [OPTIONS]

 URL is address of index page or start page.
 (e.g. index-> http://g.e-hentai.org/g/308380/d188502275/
       page -> http://g.e-hentai.org/s/ff275404a2/315989-1 )
 
 FILE is queue list file.
 
 DIRECTORY is directory to save images.

 OPTIONS are as follows:

   -d directory    directory to save images
   -D directory    base directory to create sub directory
   -f num          specify first page number for download
   -h              show this help
   -l num          specify last page number for download
   -p proxy        alternative proxy (default: \$ENV{HTTP_PROXY})
   -P file         use proxy list
   -q file         queue list file
   -r file         resume log file
   -t url          thumbnail url
   
 If the FILE or DIRECTORY begin with '-', 
 use option -q or -d, respectively. 
 
 See readme.txt for details.
 
 This script is under NYSL.
_HELP_
  }

  ### キューリストを処理する
  # 失敗時にはレジューム用のログファイルを生成する
  sub execQueueList{
    EHG::Util::printMsg("EHG::execQueueList called.", 2);
    my $queueListFile    = shift or die;
    my $cmdSaveDir       = shift;
    my $cmdBaseDir       = shift;
    my $cmdProxy         = shift;
    my $cmdProxyListFile = shift;
    my $resumeLogFile    = shift;
  
    # キューリストの各行を処理
    foreach my $queue (getQueueList(
      $queueListFile, $cmdSaveDir, $cmdProxy, $cmdProxyListFile) ){
      
      # 無効なキューをスキップ
      next unless $queue; 
      
      # キューを処理する
      next if $queue->run();
     
      # 失敗していれば，レジューム用のログファイルに書き込む
      chdir($orgCurrentDir);
      $queue->addResumeLog($resumeLogFile) if $resumeLogFlag;
    }
  }

  ### 文字コードを設定する
  sub setFSCharset{
    binmode(STDOUT, ":encoding($FSCharset)");
    binmode(STDERR, ":encoding($FSCharset)");
    binmode(STDIN,  ":encoding($FSCharset)");
  }

  ### キューリストをファイルから取得する
  sub getQueueList{
    EHG::Util::printMsg("EHG::getQueueList called.", 2);
    my $queueListFile = shift or die;
    my $cmdSaveDir = shift;
    my $cmdProxy = shift;
    my $cmdProxyListFile = shift;
    my @queueList;
  
    open(my $fh, "<", $queueListFile) # BOMへの対処のため，手動デコード
      or die "Can't open queue list file $queueListFile\n";
  
    while(my $line=<$fh>){
      $line =~ s/^\xEF\xBB\xBF//;  # UTF-8のBOMを削除
      $line = Encode::decode("utf8", $line); # 手動デコード
      $line =~ s/^\s*(.*)\s*$/$1/; # 行頭・行末のスペース/改行を削除
      next unless $line;
      
      # キューリストファイルの解析
      my @queueFields = getFieldsAsCommandArgs($line);
      my (undef, undef, $targetURL, $thumbURL,
          $firstPageNum, $lastPageNum, $saveDir, $baseDir,
          $proxy, $proxyListFile, undef) = getArgs(@queueFields);
      
      # コマンドライン引数をファイルでの指定より優先する
      $saveDir       = $cmdSaveDir       if $cmdSaveDir;
      $proxy         = $cmdProxy         if $cmdProxy;
      $proxyListFile = $cmdProxyListFile if $cmdProxyListFile;
      
      # キューの作成
      my $queue = EHG::Queue->new(
        targetURL    => $targetURL,    thumbURL      => $thumbURL,
        firstPageNum => $firstPageNum, lastPageNum   => $lastPageNum, 
        saveDir      => $saveDir,      baseDir       => $baseDir, 
        proxy        => $proxy,        proxyListFile => $proxyListFile);
      push @queueList, $queue;
    }
    close($fh);
    return @queueList;  
  }
  
  ### 文字列をコマンド引数のように解釈し，各フィールドを返す
  # ダブルクォート中のスペースは無視するが，その他のエスケープには対応しない
  sub getFieldsAsCommandArgs{
    my $str = shift or die;
    my @fields = ();
    
    while($str =~s/(.*?)"(.*?)"\s*(.*?)/$3/){
      unshift @fields, $2;
      unshift @fields, grep{$_}split /\s+/, $1;
    }
    push @fields, grep{$_}split /\s+/, $str;
    return @fields;
  }
}

#----------------------------------------------------------------------
# 作品を単位としたダウンロードキュー
#----------------------------------------------------------------------
{
  package EHG::Queue;
  use strict;
  use utf8;
  use File::Spec;
  use List::Util qw(max);
  use HTML::Entities;
  
  ### コンストラクタ
  sub new{
    my $class = shift;
    my $self = {@_};
    bless $self, $class;
    return unless $self->{targetURL};
    if($self->{targetURL}->context eq "INDEX"){
      $self->{topIndexURL} = $self->{targetURL}->clone;
      $self->{topIndexURL}->removeOptions->modifyServer;
    }
    $self->_setProxyList();
    $self->{proxy} = $self->{proxy} || $self->_extractProxy();
    
    return $self;
  }
  
  ### プロキシを切り替えながらダウンロード
  sub run{
    my $self = shift or die;
    my $success = undef;
    EHG::Util::printMsg("\nDownload start.", 1);
    EHG::Util::printMsg("Target URL: ".$self->{targetURL}, 1);

    for(my $proxyTrial=0; $proxyTrial <= $maxProxyTrial; $proxyTrial++){
      EHG::Util::printMsg("Proxy: ".$self->{proxy}, 1) if $self->{proxy};
    
      # ディレクトリ位置を元に戻す
      chdir($orgCurrentDir);
    
      # 準備してからダウンロード
      if($self->_prepare()){      
        $success = $self->_downloadArchive();
        last if $success;
      }
      
      # プロキシを変更して再挑戦
      $self->{proxy} = $self->_extractProxy();
      last unless $self->{proxy};
      EHG::Util::printMsg("Retry download.", 1) if $proxyTrial<=$maxProxyTrial;
    }
    my $pageNum = $self->{pageURL}?$self->{pageURL}->pageNum:0;
    $success? EHG::Util::printMsg("Download succeeded.", 1)
            : EHG::Util::printMsg("Download failed at page $pageNum.", 1);
    return $success;
  }
  
  ### レジューム用ログをファイルに追記する
  sub addResumeLog{
    my $self = shift or die;
    my $resumeLogFile = shift or die;
    my $url = $self->{pageURL} || $self->{topIndexURL} || $self->{targetURL};
    my $firstPageNum = 
      $self->{pageURL}?$self->{pageURL}->pageNum:$self->{firstPageNum};
    
    open(my $fh, ">>:utf8", $resumeLogFile)
      or die "Can't open resume log file $resumeLogFile.\n";
    print {$fh} $url->removeOptions;
    print {$fh} qq{ -t }.$self->{thumbURL}       if $self->{thumbURL};
    print {$fh} qq{ -f $firstPageNum};
    print {$fh} qq{ -l }.$self->{lastPageNum}    if $self->{lastPageNum};
    print {$fh} qq{ -d "}.$self->{saveDir}.qq{"} if $self->{saveDir};
    print {$fh} qq{ \n};
    close $fh;
  }
  
  ### プロキシリストの設定
  sub _setProxyList{
    EHG::Util::printMsg("EHG::Queue::_setProxyList called.",2);
    my $self = shift or die;
    
    # デフォルトのプロキシリストを読み込む
    my @proxyList = 
      map{s{^(http://)?}{http://};$_}@defaultProxyList; # 行頭に http://
    
    # ファイルが指定されていれば，プロキシリストに追加する
    if($self->{proxyListFile}){
      open(my $fh, "<", $self->{proxyListFile})
        or die "Can't open proxy list file ".$self->{proxyListFile}."\n";
      unshift @proxyList, 
         map{s{^(http://)?}{http://}; $_}           # 行頭にhttp://
         grep{$_}                                   # 空行を無視
         map{s/\s*//g; s/^\xEF\xBB\xBF//; $_}<$fh>; # 空白とBOMを削除
      close($fh);
    }
    $self->{proxyList} = \@proxyList;
  }
  
  ### プロキシリストからプロキシを取りだす
  sub _extractProxy{
    EHG::Util::printMsg("EHG::Queue::_extractProxy called.", 2);
    my $self = shift or die;
    $self->{proxy} =
       $proxyListOrder==1?
         splice @{$self->{proxyList}}, 0, 1
      :$proxyListOrder==2?
         splice @{$self->{proxyList}}, int(rand(1+@{$self->{proxyList}})), 1
      :undef;
  }
  
  ### ダウンロード前の準備を行う
  sub _prepare{
    EHG::Util::printMsg("EHG::Queue::_prepare called.", 2);
    my $self = shift or die;
    
    # URLを扱いやすい形式に変更
    $self->{targetURL}->removeOptions->modifyServer;
    
    # Mechanize オブジェクトの設定
    $self->{mech} = EHG::Mech->new($self->{targetURL}, $self->{proxy});
    
    # ダウンロード開始ページ数の設定
    $self->{firstPageNum}
      = max($self->{firstPageNum}, $self->{targetURL}->pageNum);
    
    # Indexページを元にタイトルを設定
    $self->_setTitle($self->{targetURL})
      if !$self->{saveDir} and $self->{targetURL}->context eq "INDEX";
    
    # 最初に扱うページのURLを設定
    $self->{pageURL} = $self->_getFirstPageURL unless $self->{pageURL};
    unless ($self->{pageURL}){
      EHG::Util::printMsg(
        "Can't find first page from ".$self->{targetURL}.".", 1);
      return;
    }
    
    # 個別ページを元にタイトルを設定
    $self->_setTitle($self->{pageURL})if !$self->{saveDir} and !$self->{title};
    return if !$self->{saveDir} and !$self->{title};   
    EHG::Util::printMsg("Title: ".$self->{title}, 1)
    if $self->{title} && EHG::Util::encodeFSC($self->{title});
    
    # 保存先ディレクトリ名を設定
    $self->_setSaveDir() unless $self->{saveDir};
    EHG::Util::printMsg("Save directory: ".$self->{saveDir}, 1);
  
    # 保存先ディレクトリを作成
    $self->_createSaveDir;
    
    # 保存先ディレクトリに移動
    chdir EHG::Util::encodeFSC($self->{saveDir});
  
    # ショートカットを作成
    $self->_createShortcut();
    
    return 1;
  }
  
  ### 作品をダウンロードする
  sub _downloadArchive{
    EHG::Util::printMsg("EHG::Queue::_downloadArchive called.", 2);
    my $self = shift or die;
    my $nlFlag = 0;
    my $nextPageURL = $self->{pageURL}; # 初回ループ用の値
    my ($pageNum)   = $self->{pageURL}->pageNum;
  
    # 次のページが存在する限りダウンロードを繰り返す
    for(; $pageNum<= $self->{lastPageNum} && $nextPageURL;
          $pageNum++, $nlFlag = 0){
      # nlフラグを立てるか，扱うページを次に進める
      $self->{pageURL} = $nlFlag?$self->{pageURL}->addNLOption : $nextPageURL;
      
      # お目当ての画像のURLを取得する
      my $imageURL = $self->_getImageURL() or return;
      
      # アクセス回数を減らすため，先に次のページのURLを取得する
      # 取得に失敗==最後のページに到達
      $nextPageURL = $self->_getNextPageURL();
  
      # 開始ページまでダウンロードを飛ばす
      next if $pageNum < $self->{firstPageNum};
      
      # 画像をダウンロードする
      unless($self->_downloadImage($imageURL)){ # 失敗したとき
        return if $nlFlag; # nlFlagが立っていればあきらめ
        $nlFlag = 1;                     # nlFlagを立てて
        redo;                            # 再挑戦
      }
    }
    return 1;
  }
  
  ### 作品のタイトルを設定する
  sub _setTitle{
    EHG::Util::printMsg("EHG::Queue::_setTitle called.", 2);
    my $self = shift or die;
    my $url = shift or die;
  
    $self->{mech}->get($url) or return;
    
    $self->{title} =
       $self->{mech}->content=~m{<h1 id="gj">(.*?)<}? decode_entities($1)
      :$self->{mech}->content=~m{<h1 id="gn">(.*?)<}? decode_entities($1)
      :                          decode_entities($self->{mech}->title());
  }
  
  ### 最初に扱うページのURLを取得する
  sub _getFirstPageURL{
    EHG::Util::printMsg("EHG::Queue::_getFirstPageURL called.", 2);
    my $self = shift or die;
    my $firstPageNum = $self->{firstPageNum};
    my $gid = $self->{targetURL}->gid;
    
    # 個別ページのURLが与えられていれば，そのまま
    return $self->{targetURL} if $self->{targetURL}->context eq "PAGE";
    return if $self->{targetURL}->context ne "INDEX";
    
    # ダウンロード開始ページに基づき，indexのURLを作成
    my $indexURL = int(($firstPageNum-1)/20) # 21ページ以降
      ? EHG::URL->new($self->{topIndexURL}.'?p='.int(($firstPageNum-1)/20))
      : EHG::URL->new($self->{topIndexURL});                 # 1-20ページ
  
    # Indexページから得る
    if($self->{mech}->get($indexURL)){
      return EHG::URL->new($self->{mech}->find_link(
        url_regex=>qr/\d+-$firstPageNum$/)); # URL末尾が 数字-最初のページ数
    }
    # ExHentaiサーバーの場合は，違う方法も試す
    elsif($self->{topIndexURL}->server eq "EX-HENTAI"){
      if($self->{thumbURL}){ # サムネイル画像のURLから推定
        return EHG::URL->generatePage(
          $self->{topIndexURL}, $self->{thumbURL});
      }else{ # codegen.php を利用する
        my $codegenURL = EHG::URL->generateCodegen($self->{topIndexURL});
        $self->{mech}->get($codegenURL) or return;
        my ($pageURLstr) = 
          $self->{mech}->content=~m/.*\[url=(.*?$gid-$firstPageNum)\]/;
        return EHG::URL->new($pageURLstr);
      }
    }else{
      return;
    }
  }
  
  ### 保存先ディレクトリのパスを設定する
  # マッピングできない文字がタイトルに使われている場合，
  # URLをディレクトリ名に用いる
  sub _setSaveDir{
    EHG::Util::printMsg("EHG::Queue::_setSaveDir called.", 2);
    my $self = shift;
    my $dir = File::Spec->rel2abs(
      $self->{baseDir}.EHG::Util::escapePath($self->{title}));
    my $url = $self->{topIndexURL} || $self->{targetURL};
    $self->{saveDir} = EHG::Util::encodeFSC($dir)
      ? $dir
      : $self->{baseDir}.EHG::Util::escapePath($url); 
  }
  
  ### 保存先ディレクトリを作成する
  sub _createSaveDir{
    EHG::Util::printMsg("EHG::Queue::_createSaveDir called.", 2);
    my $self = shift or die;
   
   -d EHG::Util::encodeFSC($self->{saveDir})
      ? EHG::Util::printMsg($self->{saveDir}." already exists.", 2)      # 既存
      : EHG::Util::mkpath($self->{saveDir})
        ? EHG::Util::printMsg($self->{saveDir}." is newlwy created.", 2) # 新規
        : die "Can't create ".$self->{saveDir}."\n";
  }
  
  ### インターネットショートカットの作成
  sub _createShortcut{
    EHG::Util::printMsg("EHG::Queue::_createShortcut called.", 2);
    my $self = shift or die;
    my $url = $self->{topIndexURL} || $self->{targetURL};
    
    return if glob "*.url"; # レジューム時に個別ページアドレスでの上書きを防止 
    my $fh;
    $self->{title} && EHG::Util::encodeFSC($self->{title})
      && open($fh, ">", EHG::Util::encodeFSC(
                          EHG::Util::escapePath($self->{title}).'.url'))
      or open($fh, ">", EHG::Util::encodeFSC(
                          EHG::Util::escapePath($url).'.url'))
        or die "Can't create internet shortcut.\n";
    print {$fh} "[InternetShortcut]\nURL=$url";
    close($fh);
  }
  
  ### お目当ての画像のURLを取得する
  sub _getImageURL{
    EHG::Util::printMsg("EHG::Queue::_getImageURL called.", 2);
    my $self = shift or die;
    
    $self->{mech}->get($self->{pageURL}) or return;
    return EHG::URL->new(
             (grep{   length $_->url_abs >=60               # URLが60字以上で
                   && $_->url_abs =~ m/(?:jpe?g|png|gif)$/i # 主要な画像形式の
              }$self->{mech}->find_all_images() )[0]);      # 最初の画像
  }

  ### 次のページのURLを取得する
  # このサブルーチンが偽値を返すのは，次のページへのリンクを持たない場合のみ
  # これはDL完了の印なので，戻り値に基づいて die/reuturn しないこと
  sub _getNextPageURL{
    EHG::Util::printMsg("EHG::Queue::_getNextPageURL called.", 2);
    my $self = shift or die;
    my $nextPageNum = $self->{pageURL}->pageNum + 1;
  
    # 次のページのURLを検索する
    # 直前に同URLを読み込みに成功しているので，実際には何もしないはず
    $self->{mech}->get($self->{pageURL}) or return;
  
    # リンクが見つからないのは単に最終ページに到達したとき
    return EHG::URL->new(
      $self->{mech}->find_link(
        url_regex => qr/-$nextPageNum$/)); # URL末尾が -次のページ数
  }
  
  ### 画像をダウンロードする
  sub _downloadImage{
    EHG::Util::printMsg("EHG::Queue::_downloadImage called.", 2);
    my $self = shift or die;
    my $imageURL = shift or die;
    
    # 保存するファイル名を取得する
    my $imageFileName = $self->_getImageFileName($imageURL);
    
    # ファイルの書き出し
    EHG::Util::printMsg("Download image ".$self->{pageURL}->pageNum.
      " as $imageFileName from $imageURL", 1);
    $self->{mech}->get($imageURL) or return;
    $self->{mech}->save_content($imageFileName);
    return 1;
  }
  
  ### 保存するファイル名を取得する
  sub _getImageFileName{
    EHG::Util::printMsg("EHG::Queue::_getImageFileName called.", 2);
    my $self = shift or die;
    my $imageURL = shift or die;
    my $pageNum = $self->{pageURL}->pageNum;
    
    # 保存するファイル名
    return  $namingRule==1? $imageURL->fileName
           :$namingRule==2? sprintf("%04d.%s", $pageNum, $imageURL->suffix)
           :$namingRule==3? sprintf("%04d_%s", $pageNum, $imageURL->fileName)
           :die "Can't recognize naming rule $namingRule.\n";
  }
}

#----------------------------------------------------------------------
# URI関係のパッケージ
#----------------------------------------------------------------------
{
  package EHG::URL;
  use strict;
  use utf8;
  use URI;
  use overload ('""'  => sub { ${$_[0]} });
  
  ### コンストラクタ
  sub new{
    my $class = shift;
    my $arg   = shift or return;
    my $str   = ( ref($arg) eq "WWW::Mechanize::Link"
               || ref($arg) eq "WWW::Mechanize::Image")? $arg->url_abs:$arg;
    my $self = bless \$str, $class;
    return $self;
  }
  
  ### コピーを返す
  sub clone{
    my $self = shift or die;
    return EHG::URL->new("$self");
  }
  
  ### IndexのURLとサムネイルのURLから，1ページ目のURLを作成する
  sub generatePage{
    my $class = shift or die;
    my $indexURL = shift or die;
    my $thumbURL = shift or die;
    return $class->new("http://exhentai.org/s/"
      .$thumbURL->tid."/".$indexURL->gid."-1");
  }
  
  ### IndexのURLからcodegen.phpのURLを作成する
  sub generateCodegen{
    my $class = shift or die;
    my $indexURL = shift or die;
    return $class->new("http://exhentai.org/codegen.php".
      "?gid=".$indexURL->gid."&t=".$indexURL->tid);
  }
  
  ### サーバーをLo-Fi から E-Hentaiに変更する
  # ただし，Lo-FiのIndexにおけるページ数指定オプションは落ちる
  sub modifyServer{
    my $self = shift or die;
    return $self if $self->server ne "LO-FI";
   
    if($self =~m#(.*/[^/]{10}/)\d+$#){
      $$self = $1;
    }
    
    if($self->context eq "INDEX"){
      $$self =~ s{http://lofi\.e-hentai\.org}{http://g\.e-hentai\.org};
    }elsif($self->context eq "PAGE"){
      $$self = "http://g.e-hentai.org/s/"
        .$self->tid."/".$self->gid."-".$self->pageNum;
    }
    return $self;
  }
  
  ### オプションを取り除く
  sub removeOptions{
    my $self = shift or die;
    if($self->server eq "LO-FI" and $self =~m#(.*/[^/]{10}/)\d+$#){
      $$self = $1;
    }
    $$self =~s/\?.*//;
    return $self;
  }
  
  ### nlオプションを足す
  sub addNLOption{
    my $self = shift or die;
    $$self = "$self?nl=1";
    return $self;
  }
  
  ### パスを返す
  sub path{
    my $self = shift or die;
    return URI->new($$self)->path;
  }
  
  ### コンテキストを返す
  sub context{
    my $self = shift or die;
    my $clone = $self->clone;
    $clone->removeOptions;
    return "UNKNOWN" unless $clone->path;
    return
       $clone->path =~ m#^/[^/]{2}/[^/]{2}/.*[ml]\.jpg$# ? "THUMB"
      :$clone       =~ /((jpe?g)|(gif)|(png))$/i         ? "IMAGE"
      :$clone       =~ /\d+-\d+$/                        ? "PAGE"
      :$clone       =~ m#g/\d+/\w{10}/#                  ? "INDEX"
      :$clone       =~ /codegen\.php/                    ? "CODEGEN"
      :                                                    "UNKNOWN";
  }
  
  ### サーバー種別を返す
  sub server{
    my $self = shift or die;
    return "UNKNOWN" if $self !~ /^http/;
    my $host = URI->new($$self)->host;
    return  $host =~ /exhentai/ ? "EX-HENTAI"
           :$host =~ /lofi/     ?"LO-FI"
           :$host =~ /e-hentai/ ? "E-HENTAI"
           :                      "UNKNOWN";
  }
  
  ### ページ数を返す
  sub pageNum{
    my $self = shift or die;
    my ($pageNum) = $self =~ m/\d+-(\d+)(?:\?nl=.*)?$/;
    return $pageNum?$pageNum:0;
  }
  
  ### gid (作品全体で共通のID)を返す．
  sub gid{
    my $self = shift or die;
    my $clone = $self->clone;
    my $gid = undef;
    $clone->removeOptions;
    if($self->context eq "INDEX"){
      ($gid) = $clone =~ m#/g/(\d+)/\w{10}/#;
    }elsif($self->context eq "PAGE"){
      ($gid) = $clone =~ m#(\d+)-\d+$#;
    }
    return $gid;
  }
  
  ### tid (HTML毎のID)を返す
  sub tid{
    my $self = shift or die;
    my $clone = $self->clone;
    $clone->removeOptions;
    my $tid = undef;
    if($self->context eq "INDEX"){
      ($tid) = $clone->path =~ m#^/g/\d+/(\w{10})#;
    }elsif($self->context eq "PAGE"){
      ($tid) = $clone->path =~ m#^/s/(\w{10})#;
    }elsif($self->context eq "IMAGE"){
      ($tid) = $clone->path =~ m#^/i/(\w{10})# if($self->server eq "LO-FI");
    }elsif($self->context eq "THUMB"){
      ($tid) = $clone->path =~m#^/[^/]{2}/[^/]{2}/(\w{10})#;
    }
    return $tid;
  }
  
  ### ファイル名を返す
  sub fileName{
    my $self = shift or die;
    my ($fileName) = $self =~ m{.*[/=](.+?)$}; # 最後の/および?以降の文字列
    return $fileName;
  }
  
  ### 拡張子を返す
  sub suffix{
    my $self = shift or die;
    my ($suffix) =~ m{.*\.(.+?)$}; # 最後の.以降の文字列
    return $suffix;
  }
}

#-----------------------------------------------------------------------
# 通信関係のパッケージ
#-----------------------------------------------------------------------
{
  package EHG::Mech;
  use strict;
  use utf8;
  use base qw(WWW::Mechanize);
  
  ### コンストラクタ
  sub new{
    my $class = shift;
    my $url   = shift;
    my $proxy = shift;
    my $self = $class->SUPER::new(
      cookie_jar => undef,              # クッキーは手動で設定
      onerror    => \&_printMechError); # エラー時にも処理を継続する
    $self->proxy('http', $proxy) if $proxy;
    $self->agent_alias( $agentAlias );
    $self->timeout($timeOutSec);
    $self->_setCookie($url);           # クッキーを設定
    return $self;
  }
  
  ### 通信エラー発生時，メッセージを出力するだけで処理は継続する
  sub _printMechError{
    local $" = "";
    print "Network Error: @_\n";
  }
  
  ### クッキーの設定
  sub _setCookie{
    my $self   = shift or die;
    my $url    = shift or die;
    my $cookie = ' path="/"; nw=1; tips=1;'; # バイオレンスなコンテンツ
    
    # ExHentai サーバー用  
    $cookie = ' ipb_member_id=1; domain=.exhentai.org;'.$cookie
      if $url->server eq "EX-HENTAI";
      
    # Lo-Fi 用
    #$cookie = ' xres=3;'.$cookie
    #  if $url =~ /lofi\.e-hentai\.org/;
    
    # ヘッダーにクッキー情報を追加
    EHG::Util::printMsg("Set cookie as $cookie.", 2);
    $self->add_header(Cookie=>$cookie);
  }
  
  ### Mechniazeのgetにコンテンツの検証とウェイト機能を持たせた
  sub get{
    my $self = shift or die;
    my $url  = shift or die;
    
    # すでに $url が get に成功していれば，再読み込みしない
    return $self->_verifyContent()
      if ($self->success and $self->uri->as_string() eq "$url");
    
    # get して，検証する
    EHG::Util::printMsg("get $url.", 2);
    for(1..$maxHTTPTrial){
      $self->SUPER::get("$url");
      sleep($sleepSec);
      
      return 1 if $self->success and $self->_verifyContent();
      # 問題があれば，リトライ
      EHG::Util::printMsg(
        "Retry download after $sleepFailedSec second(s).", 2);
      sleep($sleepFailedSec);
    }
    # 失敗
    return;
  }
  
  ### コンテントタイプを調べて，検証する
  sub _verifyContent{
    my $self = shift or die;
    my $url = EHG::URL->new($self->uri->as_string);
    
    if($self->ct =~ /html$/i){# コンテントがHTMLの場合
      return  $url->context eq "INDEX"  ? $self->_verifyIndex()
             :$url->context eq "PAGE"   ? $self->_verifyPage()
             :$url->context eq "CODEGEN"? $self->_verifyCodegen()
             :undef;
    }else{ # コンテントが画像等の場合
      return  $self->ct=~/gif$/i  ? $self->_verifyGIF()
             :$self->ct=~/jpe?g$/i? $self->_verifyJPG()
             :$self->ct=~/png$/i  ? $self->_verifyPNG()
             :undef;
    }
  }
  
  ### Index として正常なHTMLか検証する
  sub _verifyIndex{
    my $self = shift or die;
    
    # リンクが一定数以上あることを確認
    return $self->find_link() && @{$self->find_all_links} > 30;
  }
  
  ### Page として正常なHTMLか検証する
  sub _verifyPage{
    my $self = shift or die;
    
    # 509 (Bandwidth exceeded)エラー
    return if $self->find_image(url_regex=>qr{http://g.ehgt.org/img/509});
    
    # まれにIndexに転送されるので，リンク数の上限もチェック
    return $self->find_link() 
           && @{$self->find_all_links} > 10 && @{$self->find_all_links} < 30;
  }
  
  ### codegen.php として正常なHTMLか検証する
  sub _verifyCodegen{
    my $self = shift or die;
    return $self->content =~ m{\[b\]Title\[/b\]:};
  }
  
  ### 正しいJPG 画像か検証する
  sub _verifyJPG{
    my $self = shift or die;
    my $imageBytes = $self->content or return;
    use bytes;
    # 先頭・末尾の2バイトずつで検証
    return   if substr($imageBytes,  0, 2) ne "\xFF\xD8"; # 先頭にSOIは必須
    return 1 if substr($imageBytes, -2, 2) eq "\xFF\xD9"; # 末尾にEOIがあればOK
    
    # EOIは任意の箇所にあってもよいので全バイト列を判定に用いる
    # 最初のAPPマーカーと一致するバイト列の前にEOIがあればOK（怪しいけれど）．
    $imageBytes =~ /(.*?)\xFF[\xE0-\xEF]/;
    return 1 if $1 && $1 =~ /\xFF\xD9/;
  
    # APPセグメント（マーカー含む）までを取り除く
    while($imageBytes =~ s/.*?(\xFF[\xE0-\xEF])//){
      # APPセグメントの最初の2バイトはセグメントサイズ（バイト）
      my $size = vec(substr($imageBytes, 0, 2), 0, 16);
      # 次のセグメントに移動
      $imageBytes = substr($imageBytes, $size);
      # マーカーからはじまっていなければエラー
      return if scalar(unpack("H*", substr($imageBytes, 0,1))) ne "ff";
    }
    # 残りの部分にEOIがあるか
    return $imageBytes =~ /\xFF\xD9/;
  }
  
  ### 正しいPNG 画像か検証する
  sub _verifyPNG{
    my $self = shift or die;
    my $imageBytes = $self->content or return;
    use bytes;
    return substr($imageBytes,  0, 8)
             eq "\x89\x50\x4E\x47\x0d\x0a\x1a\x0a"  # PNGシグネチャ
      &&   substr($imageBytes, -8, 8)
             eq "\x49\x45\x4E\x44\xAE\x42\x60\x82"; # IEND
  }
  
  ### 正しいGIF 画像か検証する
  sub _verifyGIF{
    my $self = shift or die;
    my $imageBytes = $self->content or return;
    use bytes;
    return substr($imageBytes,  0, 3) eq "\x47\x49\x46" # GIFシグネチャ
      &&   substr($imageBytes, -2, 2) eq "\x00\x3B";    # Trailer
  }
}

#-----------------------------------------------------------------------
# その他のユーティリティ関数を提供するパッケージ
#-----------------------------------------------------------------------
{
  package EHG::Util;
  use strict;
  use utf8;
  use Encode;
  use File::Basename;

  ### メッセージを表示する
  # $debugLebel がメッセージのレベル以上の場合に表示する
  sub printMsg{
    return if $debugLebel < pop; # 最後の引数がメッセージのレベル
    print "$_\n" foreach @_;
  }

  ### パスとして危険な文字列をエスケープする
  sub escapePath{
    my $str = shift or die;
    $str =~s{[\\/;:\*\?\|]}{_}g; # 区切り文字は_に置換．
    $str =~tr{<>"}{()'};         # 山カッコは丸カッコ，"は'に置換．
    return $str;
  }
  
  ### デコードした文字列を返す
  sub decodeFSC{
    my $str = shift;
    utf8::is_utf8($str)? $str: decode($FSCharset, $str);
  }
  
  ### エンコードしたバイト列を返す
  # マッピングに失敗した場合は偽を返す
  sub encodeFSC{
    my $str = shift;
    my $bytes = eval{encode($FSCharset, $str, 1)};
    $@? return: return $bytes;
  }
  
  ### ディレクトリを作成する
  # File::Path::mkpathはShift_JIS系の扱いに不備があるので，簡易版を実装
  sub mkpath{
    my $path = shift;
    my $mode = shift || 0777;
    my @created;
    
    my $parent = File::Basename::dirname($path);
    push(@created, mkpath($parent, $mode))
      if (!-d encodeFSC($parent) and $path ne $parent);
    push(@created, $path) if (mkdir(encodeFSC($path), $mode));
    return @created;
  }
  
  ### 現在時刻をフォーマットされた文字列として返す
  sub getFormattedLocalTime{
   my( $sec, $min, $hour, $day, $month, $year) = localtime ( time );
   $month = $month+1;
   $year = $year+1900;
   return sprintf("%04d%02d%02d%02d%02d%02d", 
                   $year, $month, $day, $hour, $min, $sec); 
  }
}

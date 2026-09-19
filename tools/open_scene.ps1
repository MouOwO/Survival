param(
    [ValidateSet('menu','gold','wood','attribute','greater','ascension','ten_realms','main','molten','world','kit')][string]$Scene='menu',
    [ValidateSet('menu','preview','game','blender','map','prefab','review')][string]$Action='menu',
    [switch]$Check
)
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$gameRoot=[IO.Path]::GetFullPath((Join-Path $repo '../..'))
$engine=Split-Path -Parent $gameRoot
$content=Join-Path $engine 'content/dota_addons/survival'
$scenes=[ordered]@{
    gold=@{title='金币练功房';map='gold_training_room_review';folder='gold_training_room';blend='gold_training_room.blend';prefab='gold_training_room';review='manual_gold_room_review'}
    wood=@{title='木材练功房';map='wood_training_room_review';folder='wood_training_room';blend='wood_training_room.blend';prefab='wood_training_room';review='manual_wood_room_review'}
    attribute=@{title='属性练功房';map='attribute_training_room_review';folder='attribute_training_room';blend='attribute_training_room.blend';prefab='attribute_training_room';review='manual_attribute_room_review'}
    greater=@{title='大属性练功房';map='greater_attribute_training_room_review';folder='greater_attribute_training_room';blend='greater_attribute_training_room.blend';prefab='greater_attribute_training_room';review='manual_greater_attribute_room_review'}
    ascension=@{title='一至十转擂台';map='ascension_arenas_review';folder='ascension_arenas';blend='ascension_arenas.blend';prefab='ascension_arena_01';review='manual_ascension_arena_review'}
    ten_realms=@{title='一至十戒 · 700×700封闭场地';map='ten_realm_arenas_review';folder='ten_realm_arenas';blend='ten_realm_arenas.blend';prefab='ten_realm_arena_01';review='manual_ten_realm_arena_review'}
    main=@{title='十字主岛';map='main_island_review';folder='main_island';blend='main_island.blend';prefab='main_island';review='manual_main_island_review'}
    molten=@{title='熔火核心挑战房';map='molten_core_room_review';folder='molten_core_room';blend='molten_core_room.blend';prefab='molten_core_room';review='manual_molten_room_review'}
    world=@{title='旧综合测试地图';map='survival_world_v2';folder='survival_world_v2'}
    kit=@{title='仙侠组件库';map='xianxia_kit_review';folder='xianxia_kit';blend='xianxia_library.blend'}
}

function Get-SceneFile($entry,[string]$kind) {
    switch($kind) {
        preview { return Join-Path $repo ('output/'+$entry.folder+'/index.html') }
        game { return Join-Path $repo ('maps/'+$entry.map+'.vpk') }
        blender { if($entry.blend){return Join-Path $repo ('output/'+$entry.folder+'/'+$entry.blend)} }
        map { return Join-Path $content ('maps/'+$entry.map+'.vmap') }
        prefab { if($entry.prefab){return Join-Path $content ('maps/prefabs/'+$entry.prefab+'.vmap')} }
        review { if($entry.review){return Join-Path $repo ('scripts/vscripts/tests/'+$entry.review+'.lua')} }
    }
}

if($Check) {
    foreach($key in $scenes.Keys) {
        foreach($kind in @('preview','game','blender','map','prefab','review')) {
            $file=Get-SceneFile $scenes[$key] $kind
            if($file -and -not(Test-Path -LiteralPath $file -PathType Leaf)){throw "缺少文件：$file"}
        }
        Write-Output ('入口检查通过：'+$scenes[$key].title)
    }
    exit 0
}

if($Scene -eq 'menu') {
    Write-Host "`n地图与模型快捷入口`n"
    $keys=@($scenes.Keys)
    for($i=0;$i -lt $keys.Count;$i++){Write-Host ('{0}. {1}' -f ($i+1),$scenes[$keys[$i]].title)}
    $selection=Read-Host '选择场景编号（回车退出）'
    if(-not $selection){exit 0}
    if($selection -notmatch '^\d+$' -or [int]$selection -lt 1 -or [int]$selection -gt $keys.Count){throw ('请输入 1 至 '+$keys.Count+'。')}
    $Scene=$keys[[int]$selection-1]
}
$entry=$scenes[$Scene]
if($Action -eq 'menu') {
    Write-Host ("`n"+$entry.title)
    Write-Host '1. 浏览器预览（全景、近景与组件）'
    Write-Host '2. 游戏测试（复制控制台命令，打开工具）'
    if($entry.blend){Write-Host '3. Blender 工程 / 组件库'}
    Write-Host '4. 定位 Hammer 地图文件'
    if($entry.prefab){Write-Host '5. 定位 Hammer 预制件'}
    if($entry.review){Write-Host '6. 复制游戏全景预览指令（地图加载后使用）'}
    $selection=Read-Host '选择打开方式（回车退出）'
    if(-not $selection){exit 0}
    $actions=@{'1'='preview';'2'='game';'3'='blender';'4'='map';'5'='prefab';'6'='review'}
    if(-not $actions.ContainsKey($selection)){throw '无效的打开方式。'}
    $Action=$actions[$selection]
}
$file=Get-SceneFile $entry $Action
if(-not $file){throw '这个场景没有此类文件，请选择其他打开方式。'}
if(-not(Test-Path -LiteralPath $file -PathType Leaf)){throw "缺少文件：$file"}

switch($Action) {
    preview { Start-Process -FilePath $file }
    blender {
        $candidates=@($env:BLENDER_EXE,'D:/magic and love/软件/Blender/blender.exe')
        $command=Get-Command blender.exe -ErrorAction SilentlyContinue
        if($command){$candidates+= $command.Source}
        $executable=$candidates | Where-Object {$_ -and (Test-Path -LiteralPath $_ -PathType Leaf)} | Select-Object -First 1
        if(-not $executable){throw '未找到 Blender。请设置 BLENDER_EXE 为 blender.exe 的完整路径。'}
        Start-Process -FilePath $executable -ArgumentList ('"{0}"' -f $file) -WindowStyle Normal
    }
    game {
        $command='dota_launch_custom_game survival '+$entry.map
        Set-Clipboard -Value $command
        Write-Host ("`n已复制："+$command)
        if(-not(Get-Process dota2 -ErrorAction SilentlyContinue)) {
            $executable=Join-Path $gameRoot 'bin/win64/dota2.exe'
            if(-not(Test-Path -LiteralPath $executable)){throw "未找到游戏程序：$executable"}
            Start-Process -FilePath $executable -WorkingDirectory $gameRoot -WindowStyle Normal -ArgumentList @('-tools','-addon','survival','-steam','-vconsole','-condebug','+sv_cheats','1','+dota_launch_custom_game','survival',$entry.map)
        }
        $console=Join-Path $gameRoot 'bin/win64/vconsole2.exe'
        if((Test-Path -LiteralPath $console) -and -not(Get-Process vconsole2 -ErrorAction SilentlyContinue)) {
            Start-Process -FilePath $console -WindowStyle Normal
        }
        Write-Host '在 survival 工程的 VConsole 中粘贴并回车即可切图。若启动后停在工具界面，也使用这条命令。'
        if($entry.review){Write-Host '地图加载后，可重新打开菜单选 6，复制全景预览指令。'}
    }
    review {
        $command='ent_fire 0 RunScriptCode "'+"require('tests/"+$entry.review+"').start()"+'"'
        Set-Clipboard -Value $command
        Write-Host ("已复制："+$command)
        Write-Host '进入对应测试地图后，在 VConsole 中粘贴执行：拉远镜头、显示场景，并临时取消未建城墙倒计时。'
        Write-Host ('恢复普通镜头：ent_fire 0 RunScriptCode "'+"require('tests/"+$entry.review+"').finish()"+'"')
    }
    default {
        Set-Clipboard -Value $file
        Start-Process -FilePath explorer.exe -ArgumentList ('/select,"{0}"' -f $file)
        Write-Host "路径已复制：$file"
        Write-Host '在 survival 工程的 Hammer 中选择 File > Open，粘贴路径打开。'
    }
}

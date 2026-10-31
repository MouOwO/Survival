# 普通客户端排演操作适配 v02（仅代码准备）

`rehearsal_v02.py` 在独立私有模块中继承冻结的 `rehearsal.py`，父文件SHA固定为 `b15122de3441a12d283e5d3c7f0998558b2b4fbd90058fb9beb5df928f181cd7`。真实候选必须仍来自运行源码 `048a2d6b675325cd511abb01c5a122343052b2f7`；新的操作工具用自己的SHA单独绑定事务，不改该运行提交、builder／checks、原README、AUX、plan、unsigned review或canonical journal。旧工具创建的事务因code_pins不同不能与本版本混用。

普通Dota曾真实出现argv含`-vconport`却无TCP监听。这不证明启动失败。新适配允许listener缺席；若出现listener，仍须是精确owned PID及固定29028端口。CIM实际创建时间／exe／完整argv、精确native FILETIME、五文件只读锁、完整备份与CAS／ACF检查、逐路径RM和恢复规则全部继承，不因此放松。工具不连接VConsole。

默认只打印静态计划，0 OS／SDK／窗口调用、0写入：

```powershell
python tools/arcade_portrait_release_v02_20261101/rehearsal_v02.py
```

未来实际使用仅在具体签名候选和操作获批后：把原说明中CLI文件名改为`rehearsal_v02.py`，仍逐阶段显式`stage/launch/inspect/close/restore --transaction <NEW_ID> --report-sha256 <COMPLETED_SIGNED_REPORT_SHA>`；inspect还需`--label <NEW_LABEL>`。没有真实completed signed report，所有动作在OS／写入前拒绝。不得运行unsigned review。

close使用不同协议：在精确native process handle持有期间，核对CIM／argv／可选listener，然后两次选择同PID唯一visible、非最小化、标题`Dota 2`且client至少640×360的顶层主窗口，拒绝hung／重复主窗口／辅助0×0窗口。两次HWND及几何必须相同；实际PostMessage前再次核窗口owner／可见性／响应。仅向该HWND发送一次`WM_CLOSE`。不激活窗口、不发键鼠、不发C6 quit、不广播、不强杀、不自动重试。

`WM_CLOSE_REQUESTED_NOT_EXIT_VERIFIED`仅表示消息已排队，应用可能忽略它或显示正常退出确认框，须由root确认。失败、UIPI拒绝、窗口变化或hung只记录拒绝，不升级为已退出。close不观察keeper当前存活或实际持锁，回执`keeper_still_owns_file_holds=null`明确为unknown，另记`keeper_exit_required_before_restore=true`；即使keeper先异常退出而Dota仍存活，也不误写持锁肯定结论。正常路径的keeper继续以原生process handle观察真实退出后释锁；restore独立重查Dota全退出及keeper结束。close不是游戏稳定性、像素、FPS、云登录或发布验收。

仅显式close枚举顶层窗口两次，O(W)时间、O(M)候选空间；W上限4096，M为owned PID主窗口候选数。其他进程只读取窗口PID，不读取其标题／几何；只有owned窗口才读取必要属性。无初始化／稳定帧期新循环，继承keeper每2秒一次kernel wait、0 CIM／PowerShell／hash。所有原生兼容性仍待获批后的实机验证，mock测试不代表原生通过。

[PostMessageW](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-postmessagew)返回只说明排队结果；[WM_CLOSE](https://learn.microsoft.com/en-us/windows/win32/winmsg/wm-close)允许应用询问用户是否退出。[IsHungAppWindow](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-ishungappwindow)仅是系统响应启发式，本工具将其用于拒绝关闭操作，不据此声明游戏逻辑健康。

本次只准备三个新文件及隔离测试，未执行安装、签名、SDK、启动、真实Win32调用或UI消息。原先关于同步requestBarrier guard的风险不适用于本次出事的`dev_native_v02.cjs`：该wrapper只在connect前及await connect后guard，没有override requestBarrier。当前原生挂起原因仍需独立对照，不能将工具端潜在问题直接写成此次根因。

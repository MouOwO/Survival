from pathlib import Path
import json, os, queue, subprocess, sys, threading, tkinter as tk
from tkinter import ttk, messagebox
from release_packager.core import inspect, read

class App:

    def __init__(self, root, project, data):
        self.root, self.project, self.data = (root, Path(project), Path(data))
        self.queue = queue.Queue()
        self.running = False
        self.package = None
        self.lines = 0
        root.title('孤城逐晓 · 打包工具')
        root.geometry('1040x700')
        root.minsize(840, 560)
        root.configure(bg='#eef2f6')
        style = ttk.Style()
        style.theme_use('clam')
        style.configure('TFrame', background='#eef2f6')
        style.configure('TLabel', background='#eef2f6', font=('Microsoft YaHei UI', 10))
        style.configure('Title.TLabel', font=('Microsoft YaHei UI', 20, 'bold'))
        style.configure('TButton', font=('Microsoft YaHei UI', 10), padding=(16, 10))
        style.configure('Info.TLabel', foreground='#526075')
        frame = ttk.Frame(root, padding=24)
        frame.pack(fill='both', expand=True)
        ttk.Label(frame, text='孤城逐晓打包工具', style='Title.TLabel').pack(anchor='w')
        ttk.Label(frame, text='固定流程 · 自动编译与校验 · 原游廊测试发布', style='Info.TLabel').pack(anchor='w', pady=(5, 20))
        self.overview = tk.StringVar(value='正在读取当前版本…')
        ttk.Label(frame, textvariable=self.overview, wraplength=950).pack(anchor='w', pady=(0, 16))
        row = ttk.Frame(frame)
        row.pack(fill='x')
        self.buttons = []
        for title, action in [('打包', 'build'), ('打包并发布测试包', 'publish-test'), ('继续上次任务', 'resume')]:
            button = ttk.Button(row, text=title, command=lambda a=action: self.start(a))
            button.pack(side='left', padx=(0, 10))
            self.buttons.append(button)
        ttk.Button(row, text='打开包目录', command=self.open_package).pack(side='right')
        self.status = tk.StringVar(value='就绪')
        ttk.Label(frame, textvariable=self.status).pack(anchor='w', pady=(24, 8))
        self.progress = ttk.Progressbar(frame, mode='indeterminate')
        self.progress.pack(fill='x')
        area = ttk.Frame(frame)
        area.pack(fill='both', expand=True, pady=(14, 0))
        self.text = tk.Text(area, bg='#17212e', fg='#dce6ef', insertbackground='white', font=('Consolas', 10), wrap='word', borderwidth=0, padx=14, pady=12, state='disabled')
        scroll = ttk.Scrollbar(area, orient='vertical', command=self.text.yview)
        self.text.configure(yscrollcommand=scroll.set)
        scroll.pack(side='right', fill='y')
        self.text.pack(fill='both', expand=True)
        ttk.Label(frame, text='生成产物与日志会保留；发布测试包后，功能和帧率仍需实际开局验证。', style='Info.TLabel').pack(anchor='w', pady=(12, 0))
        root.protocol('WM_DELETE_WINDOW', self.close)
        root.after(100, self.read_overview)
        root.after(150, self.pump)

    def append(self, text):
        self.text.configure(state='normal')
        self.text.insert('end', text + '\n')
        self.lines += text.count('\n') + 1
        if self.lines > 2200:
            self.text.delete('1.0', '401.0')
            self.lines -= 400
        self.text.see('end')
        self.text.configure(state='disabled')

    def read_overview(self):
        try:
            info = inspect(self.project)
            self.package = Path(info['package_directory'])
            n = len(info['source']['pending_sources'])
            self.overview.set(f"当前游廊版本 {info['version']}    待发来源 {n} 项\n项目：{self.project}")
        except Exception as error:
            self.overview.set(str(error))

    def start(self, action):
        if self.running:
            return
        args = [action, '--project', str(self.project), '--data-root', str(self.data)]
        if action == 'resume':
            try:
                index = read(self.data / 'index.json')
                folder = index['jobs'][-1]['folder']
                args += ['--job', folder]
            except Exception:
                messagebox.showinfo('没有待继续任务', '请先开始一次打包。')
                return
        self.running = True
        self.progress.start(12)
        self.status.set('正在启动任务…')
        for button in self.buttons:
            button.configure(state='disabled')

        def work():
            python = Path(sys.executable)
            python = python.with_name('python.exe') if python.name.lower() == 'pythonw.exe' else python
            cmd = [str(python), '-B', '-X', 'utf8', str(Path(__file__).with_name('cli.py')), *args]
            try:
                with subprocess.Popen(cmd, cwd=self.project, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding='utf8', creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0)) as process:
                    for line in process.stdout:
                        try:
                            event = json.loads(line)
                        except ValueError:
                            event = {'event': 'log', 'message': line.strip()}
                        self.queue.put(event)
                    code = process.wait()
                    self.queue.put({'event': 'worker_exit', 'code': code})
            except Exception as error:
                self.queue.put({'event': 'failed', 'message': str(error)})
                self.queue.put({'event': 'worker_exit', 'code': 1})
        threading.Thread(target=work, daemon=False).start()

    def pump(self):
        for _ in range(100):
            try:
                event = self.queue.get_nowait()
            except queue.Empty:
                break
            kind = event.get('event')
            title = event.get('title') or event.get('message') or kind
            if kind == 'stage_started':
                self.status.set(title)
                self.append('▶ ' + title)
            elif kind in ('stage_completed', 'stage_reused'):
                self.append(('✓ ' if kind == 'stage_completed' else '↪ ') + title)
            elif kind == 'finished':
                self.status.set(event.get('message', '打包完成'))
                self.append(self.status.get())
                self.package = Path(event['package_directory']) if event.get('package_directory') else self.package
            elif kind == 'failed':
                self.status.set('任务停止，请查看下方原因')
                self.append('失败：' + str(title))
            elif kind == 'worker_exit':
                self.running = False
                self.progress.stop()
                for button in self.buttons:
                    button.configure(state='normal')
                self.read_overview()
            else:
                self.append(str(title))
        self.root.after(150, self.pump)

    def open_package(self):
        if self.package and self.package.is_dir():
            os.startfile(self.package)
        else:
            messagebox.showinfo('没有包目录', '完成打包后可在这里打开。')

    def close(self):
        if self.running:
            messagebox.showinfo('任务仍在运行', '请等待当前打包或发布结束，再关闭窗口。')
            return
        self.root.destroy()

def launch(project, data):
    root = tk.Tk()
    App(root, project, data)
    root.mainloop()

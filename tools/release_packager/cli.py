from pathlib import Path
import argparse, json, sys, traceback
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from release_packager.core import DEFAULT_DATA, Job, LocalLock, create_job, inspect, latest_job, source_state, baseline

def main(argv=None):
    parser = argparse.ArgumentParser(description='孤城逐晓专用打包工具')
    parser.add_argument('action', choices=['gui', 'inspect', 'build', 'publish-test', 'resume'])
    parser.add_argument('--project', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--data-root', type=Path, default=DEFAULT_DATA)
    parser.add_argument('--job', type=Path)
    args = parser.parse_args(argv)
    if args.action == 'gui':
        from release_packager.gui import launch
        launch(args.project, args.data_root)
        return 0
    if args.action == 'inspect':
        print(json.dumps(inspect(args.project), ensure_ascii=False))
        return 0
    with LocalLock(DEFAULT_DATA / 'builder.lock'):
        if args.job and args.action not in ('resume', 'publish-test'):
            raise ValueError('--job 仅用于继续任务或发布已生成的包')
        job = None
        if args.action == 'resume':
            job = Job(args.job) if args.job else latest_job(args.data_root, args.project)
        elif args.action == 'publish-test':
            if args.job:
                job = Job(args.job)
            elif (args.data_root / 'index.json').exists():
                previous = latest_job(args.data_root, args.project)
                if previous.state.get('stages', {}).get('build', {}).get('status') == 'done' and previous.state.get('result', {}).get('status') == 'BUILT':
                    job = previous
            if job:
                if job.project.resolve() != args.project.resolve():
                    raise ValueError('任务不属于此项目')
                current = source_state(job.project, baseline(job.project)['baseline'])
                if current['dirty_runtime'] or current['runtime_fingerprint'] != job.state.get('runtime_fingerprint'):
                    raise ValueError('源码已改变，不能发布此前的包；请先重新打包')
                job.state['publication_requested'] = True
                job.save()
        if job is None:
            job = create_job(args.project, args.action, args.data_root)
        from release_packager.backend import run
        result = run(job)
        print(json.dumps({'event': 'finished', **result}, ensure_ascii=False))
        return 0
if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except Exception as error:
        print(json.dumps({'event': 'failed', 'message': str(error)}, ensure_ascii=False), flush=True)
        raise SystemExit(1)

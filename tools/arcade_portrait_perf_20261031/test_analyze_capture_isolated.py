"""Isolated arithmetic/admission fixtures; no engine, ETW, process or network."""
from pathlib import Path
import csv,tempfile,unittest
import analyze_capture as audit


class AnalysisTests(unittest.TestCase):
    def test_interpolated_quantiles(self):
        self.assertEqual(audit.quantile([10,0],.95),9.5)
        self.assertEqual(audit.quantile([7],.99),7)
        with self.assertRaises(audit.Refused):audit.quantile([],0.5)

    def test_mean_fps_is_total_native_intervals(self):
        self.assertEqual(audit.mean_fps([10,30]),50)
        self.assertNotAlmostEqual(audit.mean_fps([10,30]),(1000/10+1000/30)/2)

    def test_one_percent_low_uses_whole_slowest_frames(self):
        values=[10]*99+[100]
        tail=audit.slow_tail(values)
        self.assertEqual(tail['frame_count'],1);self.assertEqual(tail['fps'],10)
        self.assertNotAlmostEqual(tail['fps'],1000/audit.quantile(values,.99))
        self.assertEqual(audit.slow_tail([10]*100+[100])['frame_count'],2)

    def test_correlation_constant_is_unknown_not_zero(self):
        self.assertIsNone(audit.pearson([1,1],[2,3]))
        self.assertAlmostEqual(audit.pearson([1,2,3],[2,4,6]),1)

    def test_thresholds_are_strict_greater_than(self):
        rows=[dict(FrameTime=value) for value in [16.7,25,33.3,50,50.1]]
        self.assertEqual(audit.summarize(rows)['over_ms'],{'16.7':4,'25.0':3,'33.3':2,'50.0':1})

    def test_bins_assign_native_frame_start_without_splitting(self):
        rows=[dict(CPUStartTime=time,FrameTime=10) for time in [3000,3999.9,4000]]
        bins=audit.frame_bins(rows,3000,2,1)
        self.assertEqual([row['frames'] for row in bins],[2,1])

    def fixture_csv(self,path,other_chain=False):
        columns=['ProcessID','SwapChainAddress','CPUStartTime',*audit.METRICS]
        with path.open('w',newline='',encoding='utf8') as stream:
            writer=csv.DictWriter(stream,fieldnames=columns);writer.writeheader()
            for index in range(3):
                writer.writerow(dict(ProcessID=7,SwapChainAddress='second' if other_chain and index==2 else 'one',
                    CPUStartTime=3000+index*10,**{key:10 if key=='FrameTime' else 5 for key in audit.METRICS}))

    def test_first_positive_interval_is_conservatively_discarded(self):
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/'frames.csv';self.fixture_csv(path);before=path.read_bytes()
            raw,rows,first=audit.read_frames(path,7)
            self.assertEqual((len(raw),len(rows),first['FrameTime']),(3,2,10))
            self.assertEqual(before,path.read_bytes())

    def test_multiple_swapchains_refused(self):
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/'frames.csv';self.fixture_csv(path,True)
            with self.assertRaisesRegex(audit.Refused,'multiple_or_missing_swapchains'):audit.read_frames(path,7)

    def focus(self):
        return dict(target_pid=7,target_hwnd=9,all_game_foreground=True,validation={'valid':True},
            observation_start_monotonic_seconds=0,observation_end_monotonic_seconds=30,
            samples=[dict(seconds=second+.001,foreground_pid=7,foreground_hwnd=9,game_foreground=True,
                foreground_iconic=False,target_window_valid=True,window_candidate_count=1,
                target_client_width=1600,target_client_height=900) for second in range(30)])

    def test_focus_requires_identity_visibility_and_dense_samples(self):
        focus=self.focus();result=audit.focus_summary(focus,7,30,1600,900)
        self.assertFalse(result['continuous_foreground_proven'])
        focus['samples'][5]['foreground_pid']=8
        with self.assertRaises(audit.Refused):audit.focus_summary(focus,7,30,1600,900)
        focus=self.focus();focus['samples'].pop(5)
        with self.assertRaisesRegex(audit.Refused,'focus_time_coverage_failed'):audit.focus_summary(focus,7,30,1600,900)


if __name__=='__main__':unittest.main()

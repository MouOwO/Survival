"""Insert the complete public SKU and deferred-source tables once."""
from pathlib import Path
import argparse,json


def escape(value):return str(value).replace('|','/').replace('\n','；')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--report',type=Path,required=True)
    parser.add_argument('--markdown',type=Path,required=True)
    args=parser.parse_args();data=json.loads(args.report.read_bytes());text=args.markdown.read_text('utf8')
    assert text.count('<!-- COVERAGE_TABLE -->')==text.count('<!-- DEFERRED_TABLE -->')==1
    rows=['| SKU | 现役名 / 开发名 | 渠道 | 能力与接入状态 |','| --- | --- | --- | --- |']
    for row in data['coverage']:
        titles=row['live_title'] if row['live_title']==row['development_title'] else row['live_title']+' / '+row['development_title']
        capability=row['capability']
        if capability.startswith('已映射的静态属性：'):capability='静态属性'+str(len(row['effects']))+'项，均有运行消费者'
        status=row['status'].replace('代码/目录已接入；未逐件真实购买和实机验收','接线存在，未逐件实机验收')
        rows.append('| '+ ' | '.join(escape(value) for value in [row['sku'],titles,'钱包+现金' if len(row['channels'])==2 else '钱包' if row['channels'][0]=='wallet' else '现金',capability+'；'+status])+' |')
    pending=['| 原ID | 开发名称 | 原评估状态 | 原评估中尚待接入/定义的能力（并非本轮实机结论） |','| --- | --- | --- | --- |']
    for row in data['nonready_source_rows']:
        if row['source_id']=='P002':continue
        notes=row.get('implementation_notes','').replace('\n','；')
        pending.append('| '+' | '.join(escape(value) for value in [row['source_id'],row['display_name'],row['status'],notes])+' |')
    text=text.replace('<!-- COVERAGE_TABLE -->','\n'.join(rows)).replace('<!-- DEFERRED_TABLE -->','\n'.join(pending))
    args.markdown.write_text(text,encoding='utf8',newline='\n')
    print(json.dumps(dict(status='COMPLETE_AUDIT_TABLES_RENDERED',active_skus=len(rows)-2,deferred_sources=len(pending)-2)))


if __name__=='__main__':main()

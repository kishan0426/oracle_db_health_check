
#!/bin/bash -x


#Set Variables
_set_var(){
LOGDIR=/tmp/log;
TMPDIR=/tmp/output;
HOST=`hostname`
DT=`date`
export LOGDIR TMPDIR
}
#Set Environment for database
_set_env(){
ORACLE_HOME=/data/oracle/product/11.2.0/db
ORACLE_SID=exdbx1
PATH=${ORACLE_HOME}/bin
export ORACLE_HOME ORACLE_SID PATH
}

#verify if you execute the script using oracle user.Note that UID may differ for oracle user.
_verify_user()
{
   if [ $(id -u) != 1100 ]; then
       _log "Run as oracle user"
       exit 1
   fi
}
#Database health check
_sql_report(){
#touch /tmp/Health_checkup.sql
sqlplus -S / as sysdba <<EOF
set pagesize 1100
set feedback off
set trimout on
set termout on
set term off
set linesize 200;
set pages 50
set lines 200
set pages 1000
set heading on
set timing off
SET MARKUP HTML ON SPOOL ON ENTMAP OFF -
head '<title> DAILY HEALTH CHECK </title> -
<style type="text/css"> -
table {background: #FFFFE0; font-size: 99%;} -
  th { background-color: DarkBlue; color:White} -
  td { padding: 0px; } -
</style>' -
body 'text=black bgcolor=FAFAD2 align=left' -
table 'align=center width=99% border=3 bordercolor=black bgcolor=grey'
spool /tmp/health_check.html

prompt
PROMPT

ttitle center  '<span style="background-color:DarkBlue;color:#ff3f3d;border:1px solid black;font-size:20pt;">DAILY HEALTH CHECK</span>'
PROMPT
PROMPT
col Report_Date format a30 justify center
select to_char(sysdate,'DD-MON-YYYY:HH:MI') "Report_Date" from dual;
ttitle left  '<span style="background-color:DarkBlue;color:#ff3f3d;border:1px solid black;font-size:15pt;">PROCESS AND SESSION USAGE</span>'

col RESOURCE_NAME format a20
col LIMIT_VALUE format 9999999
col CURRENT_UTILIZATION format 9999999
col MAX_UTILIZATION format 9999999
select RESOURCE_NAME,LIMIT_VALUE,CURRENT_UTILIZATION,MAX_UTILIZATION from v\$resource_limit where RESOURCE_NAME in ('processes','sessions');
PROMPT

ttitle left  '<span style="background-color:DarkBlue;color:#ff3f3d;border:1px solid black;font-size:15pt;">LONG RUNNING SESSION</span>'
PROMPT
COLUMN sid FORMAT 999 justify center
COLUMN serial# FORMAT 9999999 justify center
COLUMN machine FORMAT A30 justify center
COLUMN progress_pct FORMAT 99999999.00 justify center
COLUMN elapsed FORMAT A10 justify center
COLUMN remaining FORMAT A10 justify center
COLUMN sql_id FORMAT A10
COLUMN sql_text FORMAT A10
set numwidth 40
set long 100000000
SELECT s.sid,
s.serial#,
s.machine,
sq.sql_id,
sq.sql_text,
ROUND(sl.elapsed_seconds/60) || ':' || MOD(sl.elapsed_seconds,60) elapsed,
ROUND(sl.time_remaining/60) || ':' || MOD(sl.time_remaining,60) remaining,
ROUND(sl.sofar/sl.totalwork*100, 2) progress
FROM   v\$session s
inner join v\$session_longops sl on s.sid = sl.sid
inner join v\$sql sq on s.sql_id = sq.sql_id
and s.serial# = sl.serial#;

ttitle left  '<span style="background-color:DarkBlue;color:#ff3f3d;border:1px solid black;font-size:15pt;">CPU USAGE BY SESSION</span>'
PROMPT
set lines 250
set pages 2000
col username format a15 justify center
col program format a20 justify center
col event format a30 justify center
col sid format 99999 justify center
col SESSION_CPU_USAGE format 99999 justify center
select * from (select z.sid,nvl(z.username,'oracle-bg') as username,nvl(z.SQL_ID,'non-SQL') as SQL_ID,z.EVENT,z.program,round(sum(y.value)/100,6) as "SESSION_CPU_USAGE"
from v\$statname x
inner join v\$sesstat y on x.STATISTIC# = y.STATISTIC#
inner join v\$session z on y.SID = z.SID
where x.name in ('CPU used by this session') group by z.sid,z.username,z.SQL_ID,z.EVENT,z.program order by SESSION_CPU_USAGE desc)
where rownum < 6;

PROMPT
PROMPT

ttitle left  '<span style="background-color:DarkBlue;color:#ff3f3d;border:1px solid black;font-size:15pt;">SGA FREE MEMORY</span>'
PROMPT

select POOL,NAME,round(BYTES/1073741824,2) as MEMORY_SIZE_GB  from v\$sgastat where name like '%free memory%';

PROMPT

ttitle left  '<span style="background-color:DarkBlue;color:#ff3f3d;border:1px solid black;font-size:15pt;">IO USAGE ON DATAFILES</span>'
PROMPT

col name format a20
col DFSIZE_GB format 999999
col BLOCKS format 99999999
col PHYRDS format 99999999
col PHYWRTS format 99999999
col PHYBLKRD format 99999999
col PHYBLKWRT format 99999999
col SINGLEBLKRDS format 99999999
col AVGIOTIM format 99999999
select df.NAME,round(sum(df.bytes/1073741824),2) as DFSIZE_GB,df.BLOCKS,fs.PHYRDS,fs.PHYWRTS,fs.PHYBLKRD,fs.PHYBLKWRT,fs.SINGLEBLKRDS,fs.AVGIOTIM
from v\$datafile df
inner join v\$filestat fs on df.file#=fs.file#
group by df.NAME,df.BLOCKS,fs.PHYRDS,fs.PHYWRTS,fs.PHYBLKRD,fs.PHYBLKWRT,fs.SINGLEBLKRDS,fs.AVGIOTIM
order by fs.PHYRDS desc;

ttitle left  '<span style="background-color:DarkBlue;color:#ff3f3d;border:1px solid black;font-size:15pt;">IO USAGE BY SESSION</span>'
PROMPT

col SID format 99999
col EVENT format a20
col PROGRAM format a20
col BLOCK_GETS format 99999
col CONSISTENT_GETS format 99999
col PHYSICAL_READS format 99999
col USERNAME format a10
col process format a10
col serial# format 99999
col pid format 99999
col spid format 99999
select * from (select s.sid,s.serial#,s.EVENT,s.PROGRAM,nvl(s.USERNAME,'oracle') as USERNAME,si.BLOCK_GETS,si.CONSISTENT_GETS,si.PHYSICAL_READS
from v\$session s
inner join v\$sess_io si on s.sid=si.sid
order by si.PHYSICAL_READS desc) where rownum < 6;

ttitle left  '<span style="background-color:DarkBlue;color:#ff3f3d;border:1px solid black;font-size:15pt;">NETWORK STATS</span>'
PROMPT

select n.name,round(sum(s.value/1073741824),6) from v\$sesstat s
inner join v\$statname n on s.STATISTIC#=n.STATISTIC#
and n.name like '%SQL*Net%'
group by n.name;


ttitle left  '<span style="background-color:DarkBlue;color:#ff3f3d;border:1px solid black;font-size:15pt;">TABLESPACE USAGE > 50%</span>'
PROMPT
col TOTAL_SPACE format 999999
col TABLESPACE_NAME format a20
col TOTAL_FREE_SPACE format 999999
col UTIL_PCT format 999999
select x.TABLESPACE_NAME,round((x.bytes/1073741824),2) as TOTAL_SPACE_GB,
round(x.bytes/1073741824,2) - round(sum(y.bytes/1073741824),2) as TOTAL_FREE_SPACE_GB,
case when to_number(round((round(sum(y.bytes/1073741824),2)/round(x.bytes/1073741824,2))*100,2)) > 50 then '<font color=red>' || to_char(round((round(sum(y.bytes/1073741824),2)/round(x.bytes/1073741824,2))*100,2)) || '</font>'
when to_number(round((round(sum(y.bytes/1073741824),2)/round(x.bytes/1073741824,2))*100,2)) < 50 then '<font color=green>' || to_char(round((round(sum(y.bytes/1073741824),2)/round(x.bytes/1073741824,2))*100,2)) || '</font>'
else to_char(round((round(sum(y.bytes/1073741824),2)/round(x.bytes/1073741824,2))*100,2))
end UTIL_PCT
from dba_data_files x
inner join dba_free_space y on x.TABLESPACE_NAME = y.TABLESPACE_NAME
group by x.TABLESPACE_NAME,x.bytes/1073741824;

ttitle left  '<span style="background-color:DarkBlue;color:#ff3f3d;border:1px solid black;font-size:15pt;">REDO LOGS SWITCH FREQUENCY PER HOUR</span>'
PROMPT
col Day form a3
col h0 format 99
col h1 format 99
col h2 format 99
col h3 format 99
col h4 format 99
col h5 format 999
col h6 format 999
col h7 format 999
col h8 format 999
col h9 format 999
col h10 format 999
col h11 format 999
col h12 format 999
col h13 format 999
col h14 format 999
col h15 format 999
col h16 format 999
col h17 format 999
col h18 format 999
col h19 format 999
col h20 format 999
col h21 format 999
col h22 format 999
col h23 format 999
select to_char(first_time,'DY') as DAY,
sum(case to_char(FIRST_TIME,'hh24') when '00' then 1 else 0 end ) as h0,
sum(case to_char(FIRST_TIME,'hh24') when '01' then 1 else 0 end ) as h1,
sum(case to_char(FIRST_TIME,'hh24') when '02' then 1 else 0 end) as h2,
sum(case to_char(FIRST_TIME,'hh24') when '03' then 1 else 0 end) as h3,
sum(case to_char(FIRST_TIME,'hh24') when '04' then 1 else 0 end) as h4,
sum(case to_char(FIRST_TIME,'hh24') when '05' then 1 else 0 end) as h5,
sum(case to_char(FIRST_TIME,'hh24') when '06' then 1 else 0 end) as h6,
sum(case to_char(FIRST_TIME,'hh24') when '07' then 1 else 0 end) as h7,
sum(case to_char(FIRST_TIME,'hh24') when '08' then 1 else 0 end) as h8,
sum(case to_char(FIRST_TIME,'hh24') when '09' then 1 else 0 end) as h9,
sum(case to_char(FIRST_TIME,'hh24') when '10' then 1 else 0 end) as h10,
sum(case to_char(FIRST_TIME,'hh24') when '11' then 1 else 0 end) as h11,
sum(case to_char(FIRST_TIME,'hh24') when '12' then 1 else 0 end) as h12,
sum(case to_char(FIRST_TIME,'hh24') when '13' then 1 else 0 end) as h13,
sum(case to_char(FIRST_TIME,'hh24') when '14' then 1 else 0 end) as h14,
sum(case to_char(FIRST_TIME,'hh24') when '15' then 1 else 0 end) as h15,
sum(case to_char(FIRST_TIME,'hh24') when '16' then 1 else 0 end) as h16,
sum(case to_char(FIRST_TIME,'hh24') when '17' then 1 else 0 end) as h17,
sum(case to_char(FIRST_TIME,'hh24') when '18' then 1 else 0 end) as h18,
sum(case to_char(FIRST_TIME,'hh24') when '19' then 1 else 0 end) as h19,
sum(case to_char(FIRST_TIME,'hh24') when '20' then 1 else 0 end) as h20,
sum(case to_char(FIRST_TIME,'hh24') when '21' then 1 else 0 end) as h21,
sum(case to_char(FIRST_TIME,'hh24') when '22' then 1 else 0 end) as h22,
sum(case to_char(FIRST_TIME,'hh24') when '23' then 1 else 0 end) as h23
from v\$log_history
group by to_char(first_time,'DY')
order by case to_char(first_time,'DY')
when 'SUN' then 0
when 'MON' then 1
when 'TUE' then 2
when 'WED' then 3
when 'THU' then 4
when 'FRI' then 5
when 'SAT' then 6
end ASC;

ttitle left  '<span style="background-color:DarkBlue;color:#ff3f3d;border:1px solid black;font-size:15pt;">LOCK INFORMATION</span>'
PROMPT
col sid format 999999
col username format a15
col sql_id format a15
col event format a15
col lmode format 99 justify center
col block format 999999
col object_id format 999999
col sql_text format a20
col BLKINST format 99
col blocking_session format 99
select x.sid,x.username,x.sql_id,x.BLOCKING_INSTANCE as BLKINST,x.blocking_session,x.event,y.lmode,z.object_id,a.sql_text
from v\$session x
inner join v\$lock y on x.sid=y.sid
inner join v\$locked_object z on y.sid = z.session_id
inner join v\$sql a on x.sql_id = a.sql_id
where x.status='ACTIVE' and x.blocking_session is NOT NULL;

ttitle left  '<span style="background-color:DarkBlue;color:#ff3f3d;border:1px solid black;font-size:15pt;">HIGH RESOURCE CONSUMING SQL</span>'
PROMPT
col EVENT format a20
col AVERAGE_WAIT format 99999999
col TIME_WAITED format 99999999
column WAIT_CLASS format a15
col sid format 999999
col sql_text format a40
select * from (select se.sid,se.event,se.AVERAGE_WAIT,se.TIME_WAITED,se.WAIT_CLASS,sq.sql_text
from v\$session_event se
inner join v\$session s on s.sid = se.sid
inner join v\$sql sq on sq.sql_id = s.sql_id
where sq.sql_text not like '%select se.sid,se.event,se .AVERAGE_WAIT%'
order by AVERAGE_WAIT desc)
where rownum < 6;
ttitle left  '<span style="background-color:DarkBlue;color:#ff3f3d;border:1px solid black;font-size:15pt;">TOP LATCHES</span>'

col NAME format a20
col MISSES format 9999999
col SLEEPS format 9999999
col GETS format 9999999
col IMMEDIATE_GETS format 999999999
col IMMEDIATE_MISSES format 999999999
select * from (select name,gets,misses,sleeps,immediate_gets,immediate_misses from v\$latch order by sleeps desc) where rownum < 6;
PROMPT
ttitle left  '<span style="background-color:DarkBlue;color:#ff3f3d;border:1px solid black;font-size:15pt;">RMAN BACKUP STATUS</span>'
PROMPT
col STATUS format a15
col hrs format 999.99
select
INPUT_TYPE, STATUS,
to_char(START_TIME,'mm/dd/yy hh24:mi') start_time,
to_char(END_TIME,'mm/dd/yy hh24:mi') end_time,
elapsed_seconds/3600 hrs
from V\$RMAN_BACKUP_JOB_DETAILS
where start_time > sysdate -1
order by session_key desc;


ttitle left '<span style="background-color:DarkBlue;color:#ff3f3d;border:1px solid black;font-size:15pt;">TEMP FREE SPACE</span>'
col TABLESPACE_NAME format a20
col TABLESPACE_SIZE format 9999999
col ALLOCATED_SPACE format 9999999
col FREE_SPACE format 9999999
select TABLESPACE_NAME,TABLESPACE_SIZE/1048576 as TABLESPACE_SIZE,ALLOCATED_SPACE/1048576 as ALLOCATED_SPACE,FREE_SPACE/1048576 as FREE_SPACE from dba_temp_free_space;


ttitle left  '<span style="background-color:DarkBlue;color:#ff3f3d;border:1px solid black;font-size:15pt;">TABLE STATS LAST ANALYZED</span>'
PROMPT
select owner,count(table_name) stale_stats from all_tables where last_analyzed > sysdate - 7 group by owner order by stale_stats desc;

ttitle left  '<span style="background-color:DarkBlue;color:#ff3f3d;border:1px solid black;font-size:15pt;">INDEX STATS LAST ANALYZED</span>'
PROMPT
select table_owner,count(index_name) as stale_stats from all_indexes where last_analyzed > sysdate - 7 group by table_owner order by stale_stats desc;

ttitle left  '<span style="background-color:DarkBlue;color:#ff3f3d;border:1px solid black;font-size:15pt;">UNUSABLE INDEXES ON THE DATABASE</span>'
prompt
select index_name,table_owner from DBA_INDEXES where status='UNUSABLE';


ttitle left '<span style="background-color:DarkBlue;color:#ff3f3d;border:1px solid black;font-size:15pt;">FRA SPACE USAGE</span>'

PROMPT
set lines 200
set pages 1000
col PERCENT_SPACE_USED format 99999
col PERCENT_SPACE_RECLAIMABLE format 99999
col NUMBER_OF_FILES format 99999
select * from v\$flash_recovery_area_usage;

ttitle left '<span style="background-color:DarkBlue;color:#ff3f3d;border:1px solid black;font-size:15pt;"> FRA SPACE AVAILABLE</span>'
col NAME format a10
col SPACE_LIMIT_MB format 9999999
col SPACE_USED_MB format 9999999
col SPACE_RECLAIMABLE_MB format 9999999
select name,SPACE_LIMIT/1048576 as SPACE_LIMIT_MB,SPACE_USED/1048576 as SPACE_USED_MB,SPACE_RECLAIMABLE/1048576 as SPACE_RECLAIMABLE_MB from v\$recovery_file_dest;

ttitle left '<span style="background-color:DarkBlue;color:#ff3f3d;border:1px solid black;font-size:15pt;">ORA ERRORS</span>'
set lines 200
set pages 1000
col check_error format a20
col message_text format a50
select message_text,to_char(ORIGINATING_TIMESTAMP,'dd-mon-yy hh24:mi:ss'),
case when regexp_like(message_text,'ORA-') then 'ORA errors found'
else 'No errors'
end as check_error
from x\$dbgalertext where message_text like '%ORA-%' and ORIGINATING_TIMESTAMP > sysdate - 7 order by 1;


spool off
set markup html off
exit;
EOF
}
#Send mail 
mailx -a /tmp/health_check.html -s "DB_HEALTH_CHECK" xxx.gmail.com  
_set_var
_set_env
_verify_user
_sql_report

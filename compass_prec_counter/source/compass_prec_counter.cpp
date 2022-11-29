
#include "util/wnimisc.h"
#include "util/wconfig.h"
#include "util/optparse.h"

#include "libconndb2.h"

//
// 名前空間
//
using namespace std;
using namespace MK2;
using namespace blitz;

//
// 定数群
//
#define MK2_HOST  "localhost"
#define MK2_PORT  11112

struct ConfigData
{
  wString compass_table;
  wString compass_60min;
  wString output_table;
  wString output_counter;
};

//
// blitz math functions on arrays
//
double _m2zero(double x)
{
  return x < 0 ? 0 : x;
}

BZ_DECLARE_FUNCTION(_m2zero)

// -------
// Logger
// -------
class Logger {
public:
  enum {
    PID = 0x01,
  };
protected:
  string  m_path;
  int   m_flags;
  int   m_file_size;
  int   m_keep_count;
  mutable ofstream m_os;

public:
  Logger();
  ~Logger();
  ostream& operator () ();
  void open(const string& path, int flags = 0);
  void close();
  string tag() const;
  const string& path() const {
    return (m_path);
  }
  int flags() const {
    return (m_flags);
  }
  int fileSize() const {
    return (m_file_size);
  }
  int keepCount() const {
    return (m_keep_count);
  }
  void setFlags(int flags) {
    m_flags = flags;
  }
  void setFileSize(int file_size) {
    m_file_size = file_size;
  }
  void setKeepCount(int keep_count) {
    m_keep_count = keep_count;
  }
protected:
  void shift() const;
};

Logger  Log;

// Loggger::Logger - CTOR.
Logger::Logger() : m_flags(0), m_file_size(4 * 1024 * 1024), m_keep_count(5)
{}

// Loggger::~Logger - DTOR.
Logger::~Logger()
{
  close();
}

// Logger::operator () - Get the output stream.
ostream& Logger::operator () ()
{
  return (m_os.is_open() ? m_os : cout);
}

// Logger::open - Open the log file.
void Logger::open(const string& path, int flags)
{
  close();
  m_path = path;
  m_flags = flags;
  m_os.open(m_path.c_str(), ios_base::out|ios_base::app);
  shift();
}

// Logger::close - Close the log file.
void Logger::close()
{
  if (m_os.is_open()){
    m_os.close();
  }
}

// Logger::tag - Get the tag string.
string Logger::tag() const
{
  string s;
  char buf[128];
  struct timeval now;
  struct tm tm_buf, *tm;
  shift();
  gettimeofday(&now, NULL);
  tm = localtime_r(&now.tv_sec, &tm_buf);
  snprintf(buf, sizeof (buf), "%04d/%02d/%02d %02d:%02d:%02d.%03d",
     tm->tm_year + 1900, tm->tm_mon + 1, tm->tm_mday,
     tm->tm_hour, tm->tm_min, tm->tm_sec,
     int(now.tv_usec / 1000));
  s += buf;
  if (m_flags & PID) {
    pid_t pid;
    pid = getpid();
    snprintf(buf, sizeof (buf), " [%05d]", int(pid));
    s += buf;
  }
  s += ": ";
  return (s);
}

// Logger::shift - Shift the log file.
void Logger::shift() const
{
  int i;
  if (!m_os.is_open()){
    return;
  }
  if (m_file_size <= 0 || m_keep_count <= 0){
    return;
  }
  if (m_os.tellp() < m_file_size){
    return;
  }
  m_os.close();
  for (i = m_keep_count - 1 ; i >= 0 ; i--){
    char src[PATH_MAX], dst[PATH_MAX];
    if (i == 0){
      snprintf(src, sizeof (src), "%s", m_path.c_str());
    }else{
      snprintf(src, sizeof (src), "%s.%d", m_path.c_str(), i);
    }
    snprintf(dst, sizeof (dst), "%s.%d", m_path.c_str(), i + 1);
    (void) rename(src, dst);
  }
  m_os.open(m_path.c_str(), ios_base::out|ios_base::app);
}

//
// static
//
static void get_from_config(const wString& config, ConfigData& cngData, bool verbose)
{
  wConfig wcfg(config, '=', '#');
  wcfg.load();
  // COMPASSテーブル
  if(!wcfg.hasKey("COMPASS_TABLE")){
    throw wAppError("COMPASS_TABLE not found in " +  config);
  }
  wcfg.getParam("COMPASS_TABLE", cngData.compass_table);
  if(verbose)
    Log() << Log.tag() << "COMPASS_TABLE=" << cngData.compass_table << endl;
  // COMPASS60min
  if(!wcfg.hasKey("COMPASS_60MIN")){
    throw wAppError("COMPASS_60MIN not found in " +  config);
  }
  wcfg.getParam("COMPASS_60MIN", cngData.compass_60min);
  if(verbose)
    Log() << Log.tag() << "COMPASS_60MIN=" << cngData.compass_60min << endl;
  // OUTPUT雨量テーブル
  if(!wcfg.hasKey("OUTPUT_TABLE")){
    throw wAppError("OUTPUT_TABLE not found in " +  config);
  }
  wcfg.getParam("OUTPUT_TABLE", cngData.output_table);
  if(verbose)
    Log() << Log.tag() << "OUTPUT_TABLE=" << cngData.output_table << endl;
  // OUTPUT雨量カウンタ
  if(!wcfg.hasKey("OUTPUT_COUNTER")){
    throw wAppError("OUTPUT_COUNTER not found in " +  config);
  }
  wcfg.getParam("OUTPUT_COUNTER", cngData.output_counter);
  if(verbose)
    Log() << Log.tag() << "OUTPUT_COUNTER=" << cngData.output_counter << endl;
}

static void compass_prec_counter(MkConnection& conn, ConfigData& cngData, bool debug)
{
  // COMPASSのbasetime
  Log() << Log.tag() << "get_latest_time(" << cngData.compass_table << ")..." << endl;
  wDateTime basetime = conn.get_latest_time(cngData.compass_table);
  Log() << Log.tag() << "get_latest_time(" << cngData.compass_table << ")...done" << endl;
  // ftリスト取得
  Array<size_t,1> ft_list;
  conn.get_ft_list(cngData.compass_table, basetime, "", ft_list);
  Log() << Log.tag() << "COMPASS basetime=" << basetime.asString(wDateTime::TZ_GMT) << endl;
  Log() << Log.tag() << "COMPASS ft size=" << ft_list.size() << endl;
  if(ft_list.size() < 97){
    return;
  }
  // COMPASS読み込み
  MkAreaDesc* ad;
  size_t xsz, ysz;
  wArray<wString, wString> area_names;
  MkAreaParam ap;
  Log() << Log.tag() << "get_area_info(" << cngData.compass_table << ")..." << endl;
  conn.get_area_info(cngData.compass_table, ap);
  Log() << Log.tag() << "get_area_info(" << cngData.compass_table << ")...done" << endl;
  ap.get_area_list(area_names);
  ad = ap.get_area_desc(area_names[0]);
  xsz = ad->GetXSize();
  ysz = ad->GetYSize();
  wArray<wString, wString> elem_list;
  wArray<MkAreaFragment, MkAreaFragment> af_list;
  wArray<MkDataParam2, MkDataParam2> param_list;
  MkAreaFragment af(area_names[0], 0, 0, xsz, ysz);
  af_list.Add(af);
  elem_list.Add(cngData.compass_60min + ":FLOAT32");
  for(int i=0; i < ft_list.size(); i++){
    MkDataParam2 param(basetime, ft_list(i), "0");
    param_list.Add(param);
  }
  MkPlaneDataRaw pdr;
  Log() << Log.tag() << "read_grid_raw(" << cngData.compass_table << ",[" << af.asString() << "])..." << endl;
  conn.read_grid_raw(cngData.compass_table, param_list, af_list, elem_list, pdr);
  Log() << Log.tag() << "read_grid_raw(" << cngData.compass_table << ",[" << af.asString() << "])...done" << endl;
  // 出力データの作成
  MkPlaneDataRaw pdw;
  Array<float, 2> output_counter;
  for(unsigned int i=0; i < param_list.GetSize(); i++){
    Array<float, 2> compass_data;
    pdr.get(param_list[i], af, cngData.compass_60min, compass_data);
    if(i == 0){
      output_counter.resize(compass_data.shape()); // Make A the same size as B
      output_counter = 0;
    }
    // 欠測は-なので0に変えて置く
    compass_data = _m2zero(compass_data);
    output_counter = output_counter + compass_data;
    pdw.set(param_list[i], af, cngData.output_counter + ":FLOAT32", output_counter);
  }
  // write mk2
  if(debug == 0){
    Log() << Log.tag() << "write_grid_raw(" << cngData.output_table << ",[" << af.asString() << "])..." << endl;
    conn.write_grid_raw(cngData.output_table, pdw);
    Log() << Log.tag() << "write_grid_raw(" << cngData.output_table << ",[" << af.asString() << "])...done" << endl;
  }
}

// -----
// main
// -----
int main(int argc, char *argv[])
{
  wString pgname(basename(argv[0]));
  wString usaget("[-c <conf_file>]");
  wOptionParser op(pgname.top(), usaget.top(), "");
  op.addOption("c",1,"set configuration file.");
  op.addOption("h",1,"set mkdbd2 host. [defalut: localhost]");
  op.addOption("p",1,"set mkdbd2 port. [default: 11112]");
  op.addOption("l", 1, "Log file.");
  op.addOption("v", 0, "set verbose mode.");
  op.addOption("d", 0, "set debug mode.");
  try{
    op.parse(argc, argv);
    wString emes("Parameter error.\n");
    if(op.numNonOptArgs() != 0){
      op.throwError(emes);
    }
    wString config;
    if(op.isOptionGiven("c")){
      op.getParam("c", config);
    }else{
      op.throwError("configuration file not set.");
    }
    wString host(MK2_HOST);
    if(op.isOptionGiven("h")){
      op.getParam("h", host);
    }
    int port = MK2_PORT;
    if(op.isOptionGiven("p")){
      op.getParam("p", port);
    }
    wString logFile;
    if(op.isOptionGiven("l")){
      op.getParam("l", logFile);
    }
    bool verbose = false;
    if(op.isOptionGiven("v")){
      verbose = true;
    }
    bool debug = false;
    if(op.isOptionGiven("d")){
      debug = true;
    }
    if(logFile.len()){
      Log.open(logFile.top());
    }
    Log() << Log.tag() << "***** Logging start *****" << endl;
    Log() << Log.tag() << "debug=" << debug << endl;
    Log() << Log.tag() << "verbose=" << verbose << endl;
    Log() << Log.tag() << "host=" << host << endl;
    Log() << Log.tag() << "port=" << port << endl;
    Log() << Log.tag() << "config-file=" << config << endl;
    if (logFile.len()){
      Log() << Log.tag() << "log-file=" << logFile << endl;
    }
    // MK2へ接続
    MkConnection conn;
    Log() << Log.tag() << "connect " << host << ":" << port << "..." << endl;
    conn.connect(host, port);
    Log() << Log.tag() << "connect " << host << ":" << port << "...done" << endl;
    // configファイルの定義取得
    ConfigData cngData;
    get_from_config(config, cngData, verbose);
    // 出力はmk2だけなので関数は１つ
    compass_prec_counter(conn, cngData, debug);
  }
  catch (wException& e) {
    Log() << Log.tag()  << pgname << ": caught wException:" << e.asString() << endl;
    return (EXIT_FAILURE);
  }
  catch (exception& e) {
    Log() << Log.tag() <<  pgname << ": caught exception:" << e.what() << endl;
    return (EXIT_FAILURE);
  }
  catch (...) {
    Log() << Log.tag() << pgname << ": caught unknown exception" << endl;
    return (EXIT_FAILURE);
  }
  Log() << Log.tag() << "***** proc end normally *****" << endl;
  return (EXIT_SUCCESS);
}

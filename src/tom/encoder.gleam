import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/list
import gleam/string
import gleam/time/calendar
import gleam/time/duration

import tom

pub type TomlBuilder(a) {
  TomlBuilder(
    int: fn(Int) -> a,
    float: fn(Float) -> a,
    infinity: fn(tom.Sign) -> a,
    nan: fn(tom.Sign) -> a,
    bool: fn(Bool) -> a,
    string: fn(String) -> a,
    date: fn(calendar.Date) -> a,
    time: fn(calendar.TimeOfDay) -> a,
    /// date_time arguments date, time, and offset.
    date_time: fn(calendar.Date, calendar.TimeOfDay, tom.Offset) -> a,
    array: fn(List(a)) -> a,
    array_of_tables: fn(String, List(Dict(String, a))) -> a,
    table: fn(String, Dict(String, a)) -> a,
    inline_table: fn(Dict(String, a)) -> a,
  )
}

pub fn from_toml(builder: TomlBuilder(a), toml: tom.Toml) -> a {
  case toml {
    tom.Int(n) -> builder.int(n)
    tom.Float(n) -> builder.float(n)
    tom.Infinity(sign) -> builder.infinity(sign)
    tom.Nan(sign) -> builder.nan(sign)
    tom.Bool(bool) -> builder.bool(bool)
    tom.String(str) -> builder.string(str)
    tom.Date(date) -> builder.date(date)
    tom.Time(time) -> builder.time(time)
    tom.DateTime(date, time_of_day, offset) ->
      builder.date_time(date, time_of_day, offset)

    tom.Array(array) -> {
      array |> list.map(from_toml(builder, _)) |> builder.array
    }

    tom.ArrayOfTables(array_of_tables) -> {
      let arr =
        array_of_tables
        |> list.map(fn(table) {
          dict.map_values(table, fn(_key, value) { from_toml(builder, value) })
        })

      builder.array_of_tables("", arr)
    }

    tom.Table(table) -> {
      let converted = dict.map_values(table, fn(_, v) { from_toml(builder, v) })
      builder.table("", converted)
    }

    tom.InlineTable(inline_table) -> {
      let i =
        dict.map_values(inline_table, fn(_key, value) {
          from_toml(builder, value)
        })
      builder.inline_table(i)
    }
  }
}

pub fn to_string(toml: tom.Toml) -> String {
  let builder =
    TomlBuilder(
      int: fn(i) { int.to_string(i) },
      float: fn(f) { float.to_string(f) },
      infinity: fn(sign) {
        case sign {
          tom.Positive -> "+inf"
          tom.Negative -> "-inf"
        }
      },
      nan: fn(sign) {
        case sign {
          tom.Positive -> "+nan"
          tom.Negative -> "-nan"
        }
      },
      bool: fn(bool) {
        case bool {
          True -> "true"
          False -> "false"
        }
      },
      string: fn(str) {
        let replaced =
          str
          |> string.replace("\\", "\\\\")
          |> string.replace("\"", "\\\"")
          |> string.replace("\n", "\\n")
          |> string.replace("\t", "\\t")

        "\"" <> replaced <> "\""
      },
      date: fn(d) {
        int.to_string(d.year)
        <> "-"
        <> case calendar.month_to_int(d.month) >= 10 {
          True -> int.to_string(calendar.month_to_int(d.month))
          False -> "0" <> int.to_string(calendar.month_to_int(d.month))
        }
        <> "-"
        <> int.to_string(d.day)
      },
      time: fn(t) {
        let hours = case t.hours >= 10 {
          True -> int.to_string(t.hours)
          False -> "0" <> int.to_string(t.hours)
        }
        let minutes = case t.minutes >= 10 {
          True -> int.to_string(t.minutes)
          False -> "0" <> int.to_string(t.minutes)
        }
        let seconds = case t.seconds >= 10 {
          True -> int.to_string(t.seconds)
          False -> "0" <> int.to_string(t.seconds)
        }

        hours
        <> ":"
        <> minutes
        <> ":"
        <> seconds
        <> "."
        <> case t.nanoseconds {
          0 -> ""
          n -> int.to_string(n)
        }
      },
      date_time: fn(d, t, offset) {
        case offset {
          tom.Local -> to_string(tom.Date(d)) <> "T" <> to_string(tom.Time(t))
          tom.Offset(offset) -> {
            let seconds = duration.to_seconds(offset) |> float.round
            case seconds {
              0 -> "Z"
              _ -> {
                let abs_sec = int.absolute_value(seconds)
                let hours = abs_sec / 3600
                let mins = abs_sec % 3600 / 60

                let sign = case seconds < 0 {
                  True -> "-"
                  False -> "+"
                }

                let ofst =
                  sign
                  <> string.pad_start(int.to_string(hours), 2, "0")
                  <> ":"
                  <> string.pad_start(int.to_string(mins), 2, "0")
                to_string(tom.Date(d)) <> "T" <> to_string(tom.Time(t)) <> ofst
              }
            }
          }
        }
      },
      array: fn(arr) { "[" <> arr |> string.join(", ") <> "]" },
      array_of_tables: fn(name, tables) {
        tables
        |> list.map(fn(fields) { array_table_to_string(name, fields) })
        |> string.join("\n\n")
      },
      table: fn(name, table) { table_to_string(name, table) },
      inline_table: fn(fields) {
        let pairs =
          fields
          |> dict.to_list
          |> list.map(fn(pair) {
            let #(key, val) = pair
            key <> " = " <> val
          })

        "{ " <> pairs |> string.join(", ") <> " }"
      },
    )

  case toml {
    tom.Table(fields) ->
      fields
      |> dict.to_list
      |> list.map(fn(entry) {
        let #(name, value) = entry
        case value {
          tom.Table(inner) -> {
            let converted =
              dict.map_values(inner, fn(_, val) { from_toml(builder, val) })
            builder.table(name, converted)
          }
          _ -> from_toml(builder, value)
        }
      })
      |> string.join("\n\n")
    tom.ArrayOfTables(tables) ->
      tables
      |> list.flat_map(fn(table) {
        table
        |> dict.to_list
        |> list.map(fn(entry) {
          let #(name, value) = entry
          case value {
            tom.Table(inner) -> {
              let converted =
                dict.map_values(inner, fn(_, val) { from_toml(builder, val) })
              builder.array_of_tables(name, [converted])
            }
            _ -> from_toml(builder, value)
          }
        })
      })
      |> string.join("\n\n")
    rest -> from_toml(builder, rest)
  }
}

pub fn array_table_to_string(
  name: String,
  fields: Dict(String, String),
) -> String {
  let header = case name {
    "" -> ""
    _ -> "[[" <> name <> "]]\n"
  }

  let body =
    fields
    |> dict.to_list
    |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
    |> list.map(fn(pair) { pair.0 <> " = " <> pair.1 })
    |> string.join("\n")

  header <> body
}

pub fn table_to_string(name: String, fields: Dict(String, String)) -> String {
  let header = case name {
    "" -> ""
    _ -> "[" <> name <> "]\n"
  }

  let body =
    fields
    |> dict.to_list
    |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
    |> list.map(fn(pair) { pair.0 <> " = " <> pair.1 })
    |> string.join("\n")

  header <> body
}


package workbench

using import        "core:math"
using import        "core:fmt"
      import        "core:sort"
      import        "core:strings"
      import        "core:mem"
      import        "core:os"
      import        "core:sys/win32"

Csv_Row :: struct {
	values: [dynamic]string,
}

parse_csv_from_file :: proc(filepath: string, Record: type) -> [dynamic]Record {
	bytes, ok := os.read_entire_file(filepath);
	if !ok do return nil;

	defer delete(bytes);
	records := parse_csv(cast(string)bytes[:], Record);
	return records;
}

parse_csv :: proc(text: string, Record: type) -> [dynamic]Record {
	// todo(josh): @Optimization probably
	text = trim_whitespace(text);

	lines: [dynamic]Csv_Row;

	cur_row: Csv_Row;
	value_so_far: [dynamic]byte;

	text_idx := 0;
	for text_idx < len(text) {
		defer text_idx += 1;
		c := text[text_idx];
		value_str := cast(string)value_so_far[:];

		if c == '\\' {
			text_idx += 1;
			append(&value_so_far, text[text_idx]);
		}
		else if c == '"' {
			text_idx += 1;
			for text[text_idx] != '"' {
				append(&value_so_far, text[text_idx]);
				text_idx += 1;
			}
			text_idx += 1;

			value_str = cast(string)value_so_far[:];
			append(&cur_row.values, value_str);
			value_so_far = {}; // @Leak
			continue;
		}
		else if c == ',' {
			append(&cur_row.values, value_str);
			value_so_far = {}; // @Leak
			continue;
		}
		else if c == '\r' || c == '\n' {
			for text[text_idx] == '\r' || text[text_idx] == '\n' {
				text_idx += 1;
			}
			text_idx -= 1;
			append(&cur_row.values, value_str);
			append(&lines, cur_row);
			cur_row = {}; // @Leak
			value_so_far = {}; // @Leak
			continue;
		}

		append(&value_so_far, c);
	}

	value_str := cast(string)value_so_far[:];
	append(&cur_row.values, value_str);
	append(&lines, cur_row);
	cur_row = {}; // @Leak
	value_so_far = {}; // @Leak

	headers := lines[0];
	record_ti := type_info_of(Record);
	records: [dynamic]Record;
	for row in lines[1:] {
		record: Record;
		for field_name, column_idx in headers.values {
			str_value := row.values[column_idx];
			field_info, ok := get_struct_field_info(Record, field_name); assert(ok, aprintln("Type", type_info_of(Record), "doesn't have a field called", field_name));
			a: any;
			a.typeid = typeid_of(field_info.t);
			switch kind in a {
				case string:
					set_struct_field(&record, field_info, str_value);

				case int:
					value := parse_int(str_value);
					set_struct_field(&record, field_info, value);
				case i8:
					value := parse_i8(str_value);
					set_struct_field(&record, field_info, value);
				case i16:
					value := parse_i16(str_value);
					set_struct_field(&record, field_info, value);
				case i32:
					value := parse_i32(str_value);
					set_struct_field(&record, field_info, value);
				case i64:
					value := parse_i64(str_value);
					set_struct_field(&record, field_info, value);

				case uint:
					value := parse_uint(str_value);
					set_struct_field(&record, field_info, value);
				case u8:
					value := parse_u8(str_value);
					set_struct_field(&record, field_info, value);
				case u16:
					value := parse_u16(str_value);
					set_struct_field(&record, field_info, value);
				case u32:
					value := parse_u32(str_value);
					set_struct_field(&record, field_info, value);
				case u64:
					value := parse_u64(str_value);
					set_struct_field(&record, field_info, value);

				case f32:
					value := parse_f32(str_value);
					set_struct_field(&record, field_info, value);
				case f64:
					value := parse_f64(str_value);
					set_struct_field(&record, field_info, value);

				case bool:
					value := parse_bool(str_value);
					set_struct_field(&record, field_info, value);

				case:
					assert(false, aprintln("Unsupported record field member type:", field_info.t));
			}
		}

		append(&records, record);
	}

	return records;
}
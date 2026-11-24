# Reads `git diff -U0` output and prints the added Rust lines that may break a rule of the
# rust-rules skill, as `label: path:line: text`. A finding whose label, path and text are in the
# `seen` file is skipped, and every finding found is added to it, so one report covers them all.
# Paths listed in the `skip` file were untracked before the session and are left alone.

BEGIN {
    while ((getline key < seen) > 0) known[key] = 1
    close(seen)
    while ((getline key < skip) > 0) skipped[key] = 1
    close(skip)
}

function report(label, text,    key) {
    key = label ": " path ": " text
    if (key in known) return
    known[key] = 1
    print key >> seen
    if (shown[label] >= 10 || total >= 40) {
        hidden++
        return
    }
    shown[label]++
    total++
    printf "%s: %s:%d: %s\n", label, path, line, text
}

# Line where the file's `#[cfg(test)]` module starts, or 0. Test modules sit at the end of a file.
function test_start(file,    text, number, found) {
    while ((getline text < file) > 0) {
        number++
        if (text ~ /^[ \t]*#\[cfg\(test\)\]/) { found = number; break }
    }
    close(file)
    return found + 0
}

function check(text,    in_tests) {
    sub(/^[ \t]+/, "", text)
    if (text == "" || text ~ /^\/\//) return
    in_tests = path_is_test || (tests_from && line >= tests_from)
    if (!in_tests) {
        if (text ~ /\.unwrap\(\)|\.expect\(/) report("panic on failure", text)
        if (text ~ / as (u8|u16|u32|u64|u128|usize|i8|i16|i32|i64|i128|isize)([^A-Za-z0-9_]|$)/) report("unchecked cast (fine only when it widens)", text)
        if (text ~ /(^|[^A-Za-z0-9_])([A-Za-z0-9]+_)?(id|ids|name|key|url|code|handle): (Option<|Vec<)?(String|&('[a-z_]+ )?str)([^A-Za-z0-9_]|$)|Map<String,/) report("stringly typed (fine for wire fields and free text)", text)
        if (text ~ /match [^{;]*\.as_str\(\)|[!=]= "[A-Za-z]|"[A-Za-z0-9_]+" [!=]=/) report("string compared as a value (fine for free text)", text)
    }
    if (text ~ /\.unwrap_or_default\(\)|\.unwrap_or\((0|""|false|String::new\(\))\)|^let _ = |\.ok\(\);/) report("silent default or dropped result (fine when the spec defines the default)", text)
    if (text ~ /Result<[^;{}]*,[ \t]*(String|&'static str|\(\))[ \t]*>[ \t]*([^,> \t]|$)|Box<dyn (std::error::)?Error/) report("untyped error", text)
    if (text ~ /assert!\([ \t]*!?[^;]*\.is_(ok|err|some|none|empty)\(\)[ \t]*[,)]|assert!\([^;]*\.contains\(/) report("weak assertion (fine for human-readable prose)", text)
}

left == 0 && /^\+\+\+ / {
    path = ($0 ~ /^\+\+\+ b\//) ? substr($0, 7) : ""
    if (path in skipped) path = ""
    path_is_test = path ~ /(^|\/)(tests|benches|examples)\/|(^|\/|_)tests?\.rs$/
    tests_from = (path != "" && !path_is_test) ? test_start(path) : 0
    next
}

left == 0 && /^@@ / {
    split(substr($2, 2), old, ",")
    split(substr($3, 2), new, ",")
    left = (old[2] == "" ? 1 : old[2]) + (new[2] == "" ? 1 : new[2])
    line = new[1] + 0
    next
}

left > 0 && /^\\/ { next }

left > 0 {
    left--
    if (substr($0, 1, 1) == "+") {
        if (path != "") check(substr($0, 2))
        line++
    }
}

END {
    if (hidden > 0) printf "and %d more of the same kinds, not listed.\n", hidden
}

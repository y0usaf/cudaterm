#include "engine.cuh"

#include <stdexcept>
#include <string>

namespace {
using ct::Engine;

void feed(Engine &e, const std::string &s) {
  e.feed(reinterpret_cast<const unsigned char *>(s.data()), s.size());
}

void check(bool ok, const char *message) {
  if (!ok) throw std::runtime_error(message);
}

void expect_text(Engine &e, const std::string &expected) {
  std::string actual = e.selected_text();
  if (actual != expected)
    throw std::runtime_error("unexpected reflow selection: expected=" + expected +
                             " actual=" + actual);
}

void run_case(const char *name, void (*test)()) {
  try {
    test();
  } catch (const std::exception &error) {
    throw std::runtime_error(std::string(name) + ": " + error.what());
  }
}

void narrow_to_wide_joins_soft_rows() {
  Engine e(4, 3);
  feed(e, "abcdefghij");
  e.resize(8, 3);
  e.select(0, 0, 1, 7);
  expect_text(e, "abcdefghij");
}

void explicit_crlf_remains_hard() {
  Engine e(4, 3);
  feed(e, "abcd\r\nefgh");
  e.resize(8, 3);
  e.select(0, 0, 1, 7);
  expect_text(e, "abcd\nefgh");
}

void pending_wrap_does_not_join_existing_row() {
  Engine e(4, 3);
  feed(e, "\r\nrow");
  feed(e, "\x1b[1;1Habcd");
  e.resize(8, 3);
  e.select(0, 0, 1, 7);
  expect_text(e, "abcd\nrow");
}

void wide_edge_and_combining_survive() {
  Engine edge(4, 3);
  feed(edge, "abc\xE4\xB8\xad");
  edge.resize(8, 3);
  edge.select(0, 0, 0, 7);
  expect_text(edge, "abc\xE4\xB8\xad");

  Engine combining(4, 3);
  feed(combining, "ab\xE4\xB8\xad e\xCC\x81");
  combining.resize(8, 3);
  combining.select(0, 0, 0, 7);
  expect_text(combining, "ab\xE4\xB8\xad e\xCC\x81");
}

void history_view_reanchors_on_resize() {
  Engine e(4, 3);
  feed(e, "old-old\r\nmid-mid\r\nnew-new");
  e.scroll_view(999999);
  e.resize(8, 3);
  e.select(0, 0, 0, 7);
  expect_text(e, "old-old");
}

void alternate_stays_physical_while_primary_reflows() {
  Engine e(4, 3);
  feed(e, "primary-long");
  feed(e, "\x1b[?1049h\x1b[Halt-long");
  e.resize(8, 3);
  e.select(0, 0, 1, 7);
  expect_text(e, "alt-long");
  feed(e, "\x1b[?1049l");
  e.select(0, 0, 1, 7);
  expect_text(e, "primary-long");
}

void cursor_continues_at_new_width() {
  Engine e(4, 3);
  feed(e, "abcdef");
  e.resize(8, 3);
  feed(e, "XYZ");
  e.select(0, 0, 1, 7);
  expect_text(e, "abcdefXYZ");
}

void explicit_trailing_spaces_survive() {
  Engine e(8, 3);
  feed(e, "a   \r\nb");
  e.resize(2, 3);
  auto cells = e.cells();
  check(cells[0].cp == 'a' && cells[1].cp == ' ',
        "explicit leading row cells were lost");
  check(cells[2].cp == ' ' && cells[3].cp == ' ',
        "explicit continuation spaces were lost");
  check(cells[1].reserved & 1 && cells[2].reserved & 1 && cells[3].reserved & 1,
        "explicit spaces lost their provenance");
  check(cells[4].cp == 'b' && e.snapshot().row == 2,
        "hard break after explicit spaces moved incorrectly");
}

void erased_trailing_spaces_do_not_survive() {
  Engine e(8, 3);
  feed(e, "a   \r\nb\x1b[1;2H\x1b[K");
  e.resize(2, 3);
  e.select(0, 0, 1, 1);
  auto cells = e.cells();
  check(cells[0].cp == 'a' && cells[2].cp == 'b' &&
            e.snapshot().row == 0 && e.snapshot().col == 1,
        "erased trailing spaces created an extra reflow row");
}

void one_column_wide_glyph_uses_replacement() {
  Engine e(4, 3);
  feed(e, "a\xE4\xB8\xad" "b");
  e.resize(1, 3);
  e.select(0, 0, 2, 0);
  expect_text(e, "a\xEF\xBF\xBD" "b");
}

void prompt_anchor_and_saved_cursor() {
  Engine prompt(8, 3);
  feed(prompt, "one\r\ntwo\r\nthree\r\nfour\r\n\x1b[2J\x1b[Hprompt");
  const int history = prompt.snapshot().history_rows;
  prompt.resize(16, 3);
  check(prompt.snapshot().row == 0 && prompt.snapshot().col == 6 &&
            prompt.snapshot().history_rows == history,
        "widening pulled history into unused prompt space");
  prompt.select(0, 0, 0, 15);
  expect_text(prompt, "prompt");

  Engine saved(4, 3);
  feed(saved, "abcdef\x1b" "7\x1b[3;1Htail");
  saved.resize(8, 3);
  feed(saved, "\x1b" "8Z");
  saved.select(0, 0, 0, 7);
  expect_text(saved, "abcdefZ");
}

void incomplete_parser_state_survives_resize() {
  Engine utf(4, 3);
  feed(utf, "\xE4");
  utf.resize(8, 3);
  feed(utf, "\xB8\xAD");
  check(utf.cells()[0].cp == 0x4e2d, "resize lost partial UTF-8 state");
  feed(utf, "\x1b[3;");
  utf.resize(6, 3);
  feed(utf, "2HX");
  check(utf.cells()[13].cp == 'X', "resize lost partial CSI state");
}

void history_and_cursor_survive_height_changes() {
  Engine e(4, 2);
  feed(e, "one\r\ntwo\r\nthree\r\nfour");
  e.resize(8, 4);
  check(e.snapshot().row >= 0 && e.snapshot().row < 4,
        "cursor escaped grown screen");
  e.resize(2, 1);
  check(e.snapshot().row == 0 && e.snapshot().col >= 0 && e.snapshot().col < 2,
        "cursor escaped shrunk screen");
  e.scroll_view(999999);
  e.select(0, 0, 0, 1);
  check(!e.selected_text().empty(), "history vanished after height changes");
}
}

int main() {
  run_case("narrow_to_wide_joins_soft_rows", narrow_to_wide_joins_soft_rows);
  run_case("explicit_crlf_remains_hard", explicit_crlf_remains_hard);
  run_case("pending_wrap_does_not_join_existing_row", pending_wrap_does_not_join_existing_row);
  run_case("wide_edge_and_combining_survive", wide_edge_and_combining_survive);
  run_case("history_view_reanchors_on_resize", history_view_reanchors_on_resize);
  run_case("alternate_stays_physical_while_primary_reflows", alternate_stays_physical_while_primary_reflows);
  run_case("cursor_continues_at_new_width", cursor_continues_at_new_width);
  run_case("explicit_trailing_spaces_survive", explicit_trailing_spaces_survive);
  run_case("erased_trailing_spaces_do_not_survive", erased_trailing_spaces_do_not_survive);
  run_case("one_column_wide_glyph_uses_replacement", one_column_wide_glyph_uses_replacement);
  run_case("prompt_anchor_and_saved_cursor", prompt_anchor_and_saved_cursor);
  run_case("incomplete_parser_state_survives_resize", incomplete_parser_state_survives_resize);
  run_case("history_and_cursor_survive_height_changes", history_and_cursor_survive_height_changes);
}

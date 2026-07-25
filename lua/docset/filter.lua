local M = {}

function M.split_list(s)
  if not s or s == "" then
    return {}
  end
  local out = {}
  for part in s:gmatch("[^,]+") do
    part = part:gsub("^%s*", ""):gsub("%s*$", "")
    if part ~= "" then
      table.insert(out, part)
    end
  end
  return out
end

local function collect_all_types(entries)
  local types = {}
  for _, e in ipairs(entries) do
    types[e.type:lower()] = true
  end
  local out = {}
  for t in pairs(types) do
    table.insert(out, t)
  end
  return out
end

-- Parse "docset:type content" filter syntax.
-- Returns matched docset ids, type names, and the remaining content query.
-- docset_ids is nil when the query has no explicit filter syntax
-- (a `:` or a `,` is required), in which case content is the whole query.
function M.parse_filter(query, docsets, entries)
  if not query or query == "" then
    return nil, nil, nil
  end

  local filter_part, content = query:match("^([^%s]+)%s+(.*)$")
  if not filter_part then
    filter_part = query
    content = ""
  end

  local docset_part, type_part = filter_part:match("^([^:]*):(.*)$")
  if not docset_part then
    -- Allow multi-docset filters without a trailing colon (e.g. "lua,love2d").
    -- This makes typing the filter character-by-character in the picker feel
    -- responsive, because the comma already disambiguates the intent.
    if filter_part:find(",", 1, true) then
      docset_part = filter_part
      type_part = ""
    else
      return nil, nil, nil
    end
  end

  local docset_names = M.split_list(docset_part)
  local type_names = M.split_list(type_part)

  -- Disambiguate type vs content:
  -- If there is no space after the filter part and the type part is a known type,
  -- treat it as type. Otherwise treat it as content.
  if content == "" and type_part ~= "" and entries then
    local known_types = collect_all_types(entries)
    local is_known_type = false
    for _, t in ipairs(type_names) do
      local tl = t:lower()
      for _, kt in ipairs(known_types) do
        if kt:find(tl, 1, true) or tl:find(kt, 1, true) then
          is_known_type = true
          break
        end
      end
      if is_known_type then
        break
      end
    end
    if not is_known_type then
      content = type_part
      type_names = {}
    end
  end

  local matched_docsets = {}
  local docset_set = {}
  for _, name in ipairs(docset_names) do
    local lower = name:lower()
    for _, ds in ipairs(docsets) do
      if ds.identifier:lower() == lower or ds.name:lower() == lower or (ds.title or ""):lower() == lower then
        if not docset_set[ds.identifier] then
          docset_set[ds.identifier] = true
          table.insert(matched_docsets, ds.identifier)
        end
      end
    end
  end

  if #matched_docsets == 0 then
    return nil, nil, content or ""
  end

  return matched_docsets, type_names, content or ""
end

function M.type_matches(query_type, entry_type)
  local q = query_type:lower()
  local e = entry_type:lower()
  return e:find(q, 1, true) ~= nil or q:find(e, 1, true) ~= nil
end

function M.filter_entries(entries, filters)
  if not filters then
    return entries
  end
  local docset_set = {}
  for _, id in ipairs(filters.docsets or {}) do
    docset_set[id:lower()] = true
  end
  local type_list = filters.types or {}
  if next(docset_set) == nil and #type_list == 0 then
    return entries
  end
  return vim.tbl_filter(function(e)
    local match_docset = next(docset_set) == nil
      or docset_set[e.docset.identifier:lower()]
      or docset_set[e.docset.name:lower()]
      or docset_set[(e.docset.title or ""):lower()]
    local match_type = #type_list == 0
    if not match_type then
      for _, t in ipairs(type_list) do
        if M.type_matches(t, e.type) then
          match_type = true
          break
        end
      end
    end
    return match_docset and match_type
  end, entries)
end

function M.build_header(hints, filters, result_count)
  local parts = { hints }
  if #filters.docsets > 0 then
    table.insert(parts, "docsets:" .. table.concat(filters.docsets, ","))
  end
  if #filters.types > 0 then
    table.insert(parts, "types:" .. table.concat(filters.types, ","))
  end
  if result_count then
    table.insert(parts, "results:" .. result_count)
  end
  return table.concat(parts, "  ")
end

return M

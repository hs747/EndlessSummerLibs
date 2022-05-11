-- ExtendedTable
-- Quantum Maniac
-- Mar 26 2022

--Module
local ExtendedTable = {}

--\\ Public //--

--[[
	Clones a table. If deepClone is set to true, creates a deep clone of the table
	Deep cloning does support cyclical graphs.
	The third parameter, reachedTables, should be ignored. It is used for recursion
]]
function ExtendedTable.Clone(tbl: table, deepClone: boolean, reachedTables: {[table]: table}?): table
	local clone = {}
	reachedTables = reachedTables or {}	--Keeps track of any tables that have been cloned already to avoid infinite recursion
	reachedTables[tbl] = clone --Add "this" table to the list of reached tables

	--Loop through all values of the table and copy them into the clone
	for i,v in pairs(tbl) do
		--If deepClone is enabled, recursively clone any values that are tables
		if deepClone and type(v) == "table" then
			--Check if we already cloned this table. If so, we can just copy the reference
			--to avoid infinite recursion
			if not reachedTables[v] then
				ExtendedTable.Clone(v, true, reachedTables)
			end
			clone[i] = reachedTables[v]
		else
			clone[i] = v
		end
	end
	return clone
end

return ExtendedTable
local V2_TAG_NUMBER = 4

---@param v2Rankings ProviderProfileV2Rankings
---@return ProviderProfileSpec
local function convertRankingsToV1Format(v2Rankings, difficultyId, sizeId)
	---@type ProviderProfileSpec
	local v1Rankings = {}
	v1Rankings.progress = v2Rankings.progressKilled
	v1Rankings.total = v2Rankings.progressPossible
	v1Rankings.average = v2Rankings.bestAverage
	v1Rankings.spec = v2Rankings.spec
	v1Rankings.asp = v2Rankings.allStarPoints
	v1Rankings.rank = v2Rankings.allStarRank
	v1Rankings.difficulty = difficultyId
	v1Rankings.size = sizeId

	v1Rankings.encounters = {}
	for id, encounter in pairs(v2Rankings.encountersById) do
		v1Rankings.encounters[id] = {
			kills = encounter.kills,
			best = encounter.best,
		}
	end

	return v1Rankings
end

---Convert a v2 profile to a v1 profile
---@param v2 ProviderProfileV2
---@return ProviderProfile
local function convertToV1Format(v2)
	---@type ProviderProfile
	local v1 = {}
	v1.subscriber = v2.isSubscriber
	v1.perSpec = {}

	if v2.summary ~= nil then
		v1.progress = v2.summary.progressKilled
		v1.total = v2.summary.progressPossible
		v1.totalKillCount = v2.summary.totalKills
		v1.difficulty = v2.summary.difficultyId
		v1.size = v2.summary.sizeId
	else
		local bestSection = v2.sections[1]
		v1.progress = bestSection.anySpecRankings.progressKilled
		v1.total = bestSection.anySpecRankings.progressPossible
		v1.average = bestSection.anySpecRankings.bestAverage
		v1.totalKillCount = bestSection.totalKills
		v1.difficulty = bestSection.difficultyId
		v1.size = bestSection.sizeId
		v1.anySpec = convertRankingsToV1Format(bestSection.anySpecRankings, bestSection.difficultyId, bestSection.sizeId)
		for i, rankings in pairs(bestSection.perSpecRankings) do
			v1.perSpec[i] = convertRankingsToV1Format(rankings, bestSection.difficultyId, bestSection.sizeId)
		end
		v1.encounters = v1.anySpec.encounters
	end

	if v2.mainCharacter ~= nil then
		v1.mainCharacter = {}
		v1.mainCharacter.spec = v2.mainCharacter.spec
		v1.mainCharacter.average = v2.mainCharacter.bestAverage
		v1.mainCharacter.difficulty = v2.mainCharacter.difficultyId
		v1.mainCharacter.size = v2.mainCharacter.sizeId
		v1.mainCharacter.progress = v2.mainCharacter.progressKilled
		v1.mainCharacter.total = v2.mainCharacter.progressPossible
		v1.mainCharacter.totalKillCount = v2.mainCharacter.totalKills
	end

	return v1
end

---Parse a single set of rankings from `state`
---@param decoder BitDecoder
---@param state ParseState
---@param lookup table<number, string>
---@return ProviderProfileV2Rankings
local function parseRankings(decoder, state, lookup)
	---@type ProviderProfileV2Rankings
	local result = {}
	result.spec = decoder.decodeString(state, lookup)
	result.progressKilled = decoder.decodeInteger(state, 1)
	result.progressPossible = decoder.decodeInteger(state, 1)
	result.bestAverage = decoder.decodePercentileFixed(state)
	result.allStarRank = decoder.decodeInteger(state, 3)
	result.allStarPoints = decoder.decodeInteger(state, 2)

	local encounterCount = decoder.decodeInteger(state, 1)
	result.encountersById = {}
	for i = 1, encounterCount do
		local id = decoder.decodeInteger(state, 4)
		local kills = decoder.decodeInteger(state, 2)
		local best = decoder.decodeInteger(state, 1)
		local isHidden = decoder.decodeBoolean(state)

		result.encountersById[id] = { kills = kills, best = best, isHidden = isHidden }
	end

	return result
end

---Parse a binary-encoded data string into a provider profile
---@param decoder BitDecoder
---@param content string
---@param lookup table<number, string>
---@param formatVersion number
---@return ProviderProfile|ProviderProfileV2|nil
local function parse(decoder, content, lookup, formatVersion) -- luacheck: ignore 211
	-- For backwards compatibility. The existing addon will leave this as nil
	-- so we know to use the old format. The new addon will specify this as 2.
	formatVersion = formatVersion or 1
	if formatVersion > 2 then
		return nil
	end

	---@type ParseState
	local state = { content = content, position = 1 }

	local tag = decoder.decodeInteger(state, 1)
	if tag ~= V2_TAG_NUMBER then
		return nil
	end

	---@type ProviderProfileV2
	local result = {}
	result.isSubscriber = decoder.decodeBoolean(state)
	result.summary = nil
	result.sections = {}
	result.progressOnly = false
	result.mainCharacter = nil

	local sectionsCount = decoder.decodeInteger(state, 1)
	if sectionsCount == 0 then
		---@type ProviderProfileV2Summary
		local summary = {}
		summary.zoneId = decoder.decodeInteger(state, 2)
		summary.difficultyId = decoder.decodeInteger(state, 1)
		summary.sizeId = decoder.decodeInteger(state, 1)
		summary.progressKilled = decoder.decodeInteger(state, 1)
		summary.progressPossible = decoder.decodeInteger(state, 1)
		summary.totalKills = decoder.decodeInteger(state, 2)

		result.summary = summary
	else
		for i = 1, sectionsCount do
			---@type ProviderProfileV2Section
			local section = {}
			section.zoneId = decoder.decodeInteger(state, 2)
			section.difficultyId = decoder.decodeInteger(state, 1)
			section.sizeId = decoder.decodeInteger(state, 1)
			section.partitionId = decoder.decodeInteger(state, 1) - 128
			section.totalKills = decoder.decodeInteger(state, 2)

			local specCount = decoder.decodeInteger(state, 1)
			section.anySpecRankings = parseRankings(decoder, state, lookup)

			section.perSpecRankings = {}
			for j = 1, specCount - 1 do
				local specRankings = parseRankings(decoder, state, lookup)
				table.insert(section.perSpecRankings, specRankings)
			end

			table.insert(result.sections, section)
		end
	end

	local hasMainCharacter = decoder.decodeBoolean(state)
	if hasMainCharacter then
		---@type ProviderProfileV2MainCharacter
		local mainCharacter = {}
		mainCharacter.zoneId = decoder.decodeInteger(state, 2)
		mainCharacter.difficultyId = decoder.decodeInteger(state, 1)
		mainCharacter.sizeId = decoder.decodeInteger(state, 1)
		mainCharacter.progressKilled = decoder.decodeInteger(state, 1)
		mainCharacter.progressPossible = decoder.decodeInteger(state, 1)
		mainCharacter.totalKills = decoder.decodeInteger(state, 2)
		mainCharacter.spec = decoder.decodeString(state, lookup)
		mainCharacter.bestAverage = decoder.decodePercentileFixed(state)

		result.mainCharacter = mainCharacter
	end

	local progressOnly = decoder.decodeBoolean(state)
	result.progressOnly = progressOnly

	if formatVersion == 1 then
		return convertToV1Format(result)
	end

	return result
end
--- the utf8 global is not available, so we polyfill utf8.offset so we can correctly find prefixes of utf8 strings
---@param str string
---@param index number
---@return number|nil
local function Utf8Offset(str, index)
	local len = #str

	if index <= 0 or index > len then
		return nil -- Out of bounds
	end

	-- Move forward to the nth character
	local count = 0
	for i = 1, len do
		local byte = string.byte(str, i)
		local isContinuationByte = byte >= 128 and byte < 192
		if not isContinuationByte then
			count = count + 1
			if count == index then
				return i
			end
		end
	end

	return nil -- If the nth character is not found
end

---@param table table<string, string> raw data table with character name prefixes as keys
---@param length number the number of complete characters to include in the prefix
---@return fun(characterName: string):string|nil getChunk function to retrieve a character chunk by prefix using a complete character name
local function getChunkLookup(table, length)
	return function(characterName)
		local startOfNextCharacter = Utf8Offset(characterName, length + 1)

		local prefix
		if startOfNextCharacter == nil then
			prefix = characterName
		else
			prefix = string.sub(characterName, 1, startOfNextCharacter - 1)
		end

		return table[prefix]
	end
end

local lookup = {'Unknown-Unknown','Shaman-Elemental','Druid-Guardian','DeathKnight-Unholy','DeathKnight-Frost','Hunter-BeastMastery','Evoker-Devastation','Paladin-Retribution','Monk-Windwalker','Priest-Holy','Shaman-Restoration','Hunter-Marksmanship',}
local provider = {region='US',realm='Eitrigg',name='US',type='weekly',zone=53,date='2026-09-22',data={Al='Alys:BAAANQADCggIEQAAAA==.',
Am='Amaniatres:BAAANQAECgYJEQAAAA==.Amperage:BAAANQADCgUIEAABNQAECgYJEQABAAAAAA==.',
An='Anaan:BAAANQADCgYIBgAAAA==.Anahera:BAAANQADCgcIBwABNQAECgQIBwABAAAAAA==.Anzhelina:BAAANQADCggJFgAAAA==.',
Ap='Apis:BAAANQAECgIIAgAAAA==.',
Ar='Arihana:BAAANQADCgcIFwAAAA==.',
As='Asapshocky:BAABNQAECoEYAAICAAkKAx5GFQADAwACAAkKAx5GFQADAwAAAA==.',
Ba='Baahp:BAAANQAECgQJBAAAAA==.Barley:BAAANQABCgIIAgAAAA==.',
Be='Belgerra:BAAANQAECgYJDQAAAA==.Bellabelle:BAAANQADCgQJBgAAAA==.Bevian:BAAANQADCgEIAQABNQAECgQIBAABAAAAAA==.',
Bi='Biggiepants:BAAANQAECgQJCAAAAA==.Biggnome:BAAANQADCgYIBgABNQADCgUICQABAAAAAA==.Bighead:BAAANQADCgQIBAABNQADCgUICQABAAAAAA==.Biollante:BAAANQADCgYICAAAAA==.',
Bo='Bootyßandaid:BAAANQAECgUICgAAAA==.',
Bu='Buckis:BAAANQADCgcJHgAAAA==.',
Ca='Camderags:BAAANQADCggICAAAAA==.Canon:BAAANQADCggIEAAAAA==.Catasucked:BAAANQADCgMIAwAAAA==.',
Ch='Chillin:BAAANQADCgEIAQAAAA==.Choggy:BAAANQAECgUJEAAAAA==.',
Ci='Cindrõz:BAAANQAECgQIBAAAAA==.',
Co='Conception:BAAANQADCgYIDAABNQAECgQICAABAAAAAA==.Cough:BAAANQADCgUICQAAAA==.',
Cr='Crinklecut:BAAANQAECgIJBAAAAA==.Crow:BAAANQAECgcJEgAAAA==.',
Da='Danielallen:BAAANQAECgQJBgAAAA==.',
De='Deadlybeard:BAAANQADCgQICQABNQAECgYJDgABAAAAAA==.Deadlywrath:BAAANQAECgYJDgAAAA==.Deadmenace:BAAANQADCgYJCwAAAA==.Decåying:BAAANQAECgYJDgAAAA==.Deni:BAAANQADCggIEAAAAA==.',
Di='Diagnosis:BAAANQAECgIIAwAAAA==.',
Do='Donnabb:BAAANQAECgQICAAAAA==.Donteatbees:BAAANQAECgIJAwAAAA==.Dop:BAAANQAECgQIBwAAAA==.Doran:BAAANQADCgUIBQAAAA==.Dottierotten:BAAANQADCgcJDQAAAA==.',
Dr='Drenrah:BAAANQAECgUJCQAAAA==.',
Ed='Edend:BAAANQADCgUICgAAAA==.',
Ei='Eiduartpaw:BAAANQAECgUJCAAAAA==.',
El='Electracutie:BAAANQAECgQJBgAAAA==.Elementdemon:BAAANQAECgUJDgAAAA==.',
En='Enthalpy:BAAANQAECgYIEgAAAA==.',
Es='Esperzoa:BAAANQAECgMJBQAAAA==.',
Eu='Eucalicdes:BAABNQAECoEXAAIDAAgKgBVrCgAIAgADAAgKgBVrCgAIAgAAAA==.',
Ev='Evøkër:BAAANQABCgIIAgAAAA==.',
Ez='Ezra:BAAANQADCgUICgAAAA==.',
Fa='Falshin:BAAANQADCggICAAAAA==.Fancy:BAAANQADCgYIGQAAAA==.Fangyi:BAAANQAECgYJDgAAAA==.',
Fi='Fiction:BAAANQAECggJDAAAAA==.',
Fl='Florita:BAAANQAECgEJAQAAAA==.',
Fo='Fordinn:BAAANQAECgQJEQAAAA==.',
Fr='Fren:BAAANQAECgQIBAAAAA==.',
Fu='Furrypunch:BAAANQABCgIIAgABNQABCgIIAgABAAAAAA==.',
Ga='Gasket:BAABNQAECoEZAAMEAAgKwBq7HgBvAgAEAAgKWBq7HgBvAgAFAAUKRhIfPwADAQAAAA==.',
Gh='Ghostdragona:BAAANQABCgEJAQAAAA==.',
Gr='Graceful:BAAANQAECgUJDAAAAA==.Grit:BAAANQAECgMJAwAAAA==.',
Ha='Handicap:BAAANQAECgEIAQABNQAECgIIAwABAAAAAA==.Hark:BAABNQAECoEZAAIGAAgKcBnVKwCEAgAGAAgKcBnVKwCEAgAAAA==.Harpin:BAAANQAECgYJDQAAAA==.Harvin:BAAANQAECgQIBwAAAA==.',
He='Heals:BAAANQAECggICAAAAA==.Heisenburgg:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.Helanua:BAAANQAECgUJBwAAAA==.',
Hi='Highlight:BAAANQADCggJGQAAAA==.Hippopotamus:BAAANQADCgIIAgAAAA==.Hit:BAAANQAECgEIAQAAAA==.',
Ho='Holyish:BAAANQAECgIJAgAAAA==.Holyrollers:BAAANQADCgEJAQAAAA==.Holytide:BAAANQAECgMJBAAAAA==.Hops:BAAANQADCgQIBAAAAA==.Hornsie:BAAANQADCgIIAgAAAA==.Horrorfang:BAAANQAECgQIBwAAAA==.',
['Hä']='Häwke:BAAANQADCgQIBwAAAA==.',
Ib='Ibaar:BAACNQAFFIELAAIHAAUK0iIKAQD6AQAHAAUK0iIKAQD6AQA1AAQKgSAAAgcACQozIm4DAE0DAAcACQozIm4DAE0DAAAA.',
Ic='Icialiaa:BAAANQADCgIIAgABNQAECgMJAgABAAAAAA==.',
In='Inno:BAAANQAECgUJBQAAAA==.',
It='Ithacus:BAAANQAECgUJDgAAAA==.Itspriesty:BAAANQAECgEIAQAAAA==.',
Ja='Janari:BAAANQADCgYIBgAAAA==.Jandaar:BAAANQADCgYICQAAAA==.Jatt:BAAANQADCggICAAAAA==.Jattwuzza:BAAANQADCgQIBAAAAA==.',
Jd='Jdawgprime:BAAANQABCgQIBAAAAA==.',
Ji='Jilkaeden:BAAANQAECgEJAQAAAA==.',
Jo='Jorek:BAAANQAECgYJDgAAAA==.',
Ka='Kaiva:BAAANQAECgQIBwAAAA==.Kavik:BAAANQAECgIIAgAAAA==.',
Ke='Keflá:BAAANQADCgUJBQAAAA==.Kelencye:BAAANQAECgIJAwAAAA==.',
Kh='Khaas:BAAANQAECgEIAQAAAA==.Khanloa:BAAANQADCgUIBQAAAA==.Kheleze:BAAANQADCgYJBgABNQAECgQIBgABAAAAAA==.',
Ki='Killshot:BAAANQADCgYJCAAAAA==.',
Ko='Korihor:BAAANQAECgMJBQAAAA==.',
Kr='Krestus:BAAANQAECgUJCwAAAA==.Krispy:BAAANQAECgIJAgAAAA==.Krispyy:BAAANQADCgYIBgAAAA==.Krix:BAAANQADCgcIBgAAAA==.',
Ku='Kuroji:BAAANQABCgEIAQAAAA==.',
La='Laerin:BAAANQAECgIJAwAAAA==.Landreielea:BAAANQAECgQIBQAAAA==.Laxus:BAAANQAECgUICQAAAA==.',
Le='Lerenor:BAAANQADCgEIAQAAAA==.Levophed:BAAANQAECgUJCAAAAA==.',
Li='Lily:BAAANQAECgQJBQAAAA==.Linnt:BAAANQADCgcJGAAAAA==.Liyara:BAABNQAECoEZAAIIAAgKcyMgGQAVAwAIAAgKcyMgGQAVAwAAAA==.',
Ll='Llorsa:BAAANQAECgQJBQAAAA==.Lltoj:BAAANQADCgEIAQAAAA==.',
Lu='Lusavahza:BAAANQADCgUIBgAAAA==.',
['Lä']='Ländrei:BAAANQAECgIJAgABNQAECgQIBQABAAAAAA==.',
Ma='Macy:BAAANQABCgIIAgAAAA==.Mahralla:BAAANQADCgQIBAAAAA==.Maikagond:BAAANQADCgYIBgABNQAECgUIDAABAAAAAA==.Makaria:BAAANQAECgIJBAAAAA==.Malbisa:BAAANQADCggJDgAAAA==.Malphoz:BAAANQADCgUIBQAAAA==.Mandragora:BAAANQADCgcJDgAAAA==.Marli:BAAANQADCgIIAgAAAA==.',
Mi='Mickey:BAABNQAECoEXAAIJAAcK+BkEFwAOAgAJAAcK+BkEFwAOAgAAAA==.Mikiik:BAAANQAECgQJBQAAAA==.Mikk:BAAANQADCgIJAgAAAA==.Mildoo:BAAANQAECgQJBwAAAA==.Milkymoo:BAAANQADCgUIBQABNQAFFAUIDwAKAH4WAA==.',
Mo='Monq:BAAANQAECgUJBgAAAA==.Moón:BAAANQAECgQJCAAAAA==.',
['Mî']='Mîlk:BAAANQADCgIIAgAAAA==.',
Na='Narus:BAAANQADCggIFwABNQAECgQJEQABAAAAAA==.',
Ne='Neviaa:BAAANQAECgQJBAAAAA==.',
Ni='Nickypoo:BAAANQADCgYICQAAAA==.Nightmenace:BAAANQAECgQIBgAAAA==.Niq:BAAANQAECgEIAQAAAA==.',
No='Nothealster:BAAANQAECgUJCQAAAA==.Novacane:BAAANQAECgEIAgAAAA==.',
Ob='Obitrice:BAAANQAECgUJCAAAAA==.Obsidiian:BAAANQAECgMIBAAAAA==.Obsidion:BAAANQADCggIGAABNQAECgQJEQABAAAAAA==.',
Od='Odie:BAAANQAECgIIAgAAAA==.',
Or='Organdonor:BAAANQAECgYJCwAAAA==.',
Os='Ossin:BAAANQAECgEIAQAAAA==.',
Ov='Overwhtrice:BAAANQADCggJEAAAAA==.',
Pa='Pantherlilly:BAAANQADCgYIDwAAAA==.',
Pe='Perry:BAAANQAECgIIAwAAAA==.',
Po='Pozufuma:BAAANQAECgQJBQAAAA==.',
Ps='Psychomantis:BAAANQAECgUJDQAAAA==.',
Ra='Ravenbear:BAAANQAECgMJBQAAAA==.',
Re='Redpool:BAAANQAECgUJCQAAAA==.Retrix:BAAANQAECgQICAAAAA==.Revorra:BAAANQAECgQICAABNQAECgQJEQABAAAAAA==.',
Ri='Ristvakbaen:BAAANQAECgYJEAAAAA==.',
Ro='Robynlee:BAAANQAECgQICAAAAA==.Rohini:BAAANQADCgQIBgAAAA==.Rovik:BAAANQAECgMJAwAAAA==.',
Sc='Sceryna:BAAANQAECgYJEQAAAA==.Schiftly:BAAANQADCgQIBAAAAA==.Scrmndemn:BAAANQAECgYJDAAAAA==.',
Se='Sef:BAAANQAECgUICQAAAA==.Serpent:BAAANQADCgUIBQAAAA==.',
Sh='Shamtastical:BAAANQAECgQJBgABNQAECgQICAABAAAAAA==.Shikita:BAAANQAECgQJBgAAAA==.Shimadin:BAACNQAFFIEFAAIIAAMKRRFrCQDsAAAIAAMKRRFrCQDsAAA1AAQKgSEAAggACQo0ImUYABoDAAgACQo0ImUYABoDAAAA.Shimsong:BAAANQADCggIDQABNQAFFAMIBQAIAEURAA==.Shmerek:BAAANQAECgYJDgAAAA==.',
Si='Sierramist:BAAANQAECgUJCwAAAA==.Silverpacem:BAAANQADCgcIBwAAAA==.Silverstream:BAAANQAECgcJEAAAAA==.',
So='Solbin:BAAANQAECgQICwABNQAECgcJEgABAAAAAA==.Solexine:BAAANQADCgQIBAAAAA==.Solitudé:BAAANQAECgIJAgABNQAECggIGQAFAOIiAA==.Soteirian:BAAANQAECgUIDAAAAA==.',
Sp='Spiritlinkin:BAAANQAECgEJAgAAAA==.',
St='Stalariais:BAAANQADCgYIBgABNQAECgYICAABAAAAAA==.Steve:BAAANQAECgQIBQAAAA==.',
Su='Sugardawn:BAAANQAECgQIBAAAAA==.Sugarkitty:BAAANQADCgcIBwAAAA==.Supereclipse:BAAANQAECgQJBQAAAA==.',
Sy='Sydvicious:BAAANQAECgYICgAAAA==.',
Ta='Taintedwater:BAAANQAECgMJAgAAAA==.Tairnanach:BAAANQADCgYIDgAAAA==.Taladiir:BAAANQADCggJEAAAAA==.Tayger:BAAANQADCgcJEAAAAA==.',
Td='Tdog:BAAANQADCgcIDgAAAA==.',
Te='Tecks:BAAANQAECgYJDgAAAA==.Teslá:BAAANQAECgEIAQAAAA==.',
Th='Thayo:BAAANQADCgcJEAAAAA==.Themajor:BAAANQAECgEJAQAAAA==.Therossyas:BAAANQADCgYJCAAAAA==.Thezuggest:BAAANQADCgMJAwAAAA==.Thicctotems:BAABNQAECoEcAAMLAAgK2B/EHgCcAgALAAgK2B/EHgCcAgACAAEKbQnIzwBBAAAAAA==.Threat:BAAANQAECgYIEAAAAA==.Thungerthi:BAAANQADCgEIAQAAAA==.',
Ti='Tiamaat:BAAANQAECgYJDgAAAA==.Tinysanta:BAAANQAECgIIBAAAAA==.Titus:BAAANQADCgYICQAAAA==.',
To='Toatani:BAAANQADCgMJAwABNQAECgQIBwABAAAAAA==.Tokkaebi:BAAANQABCgIIAgAAAA==.Torvar:BAAANQADCggIDwAAAA==.',
Ty='Tyletos:BAAANQAECgcJEgAAAA==.',
Ug='Ugolok:BAAANQADCgcIDAAAAA==.',
Ur='Uriél:BAAANQADCgQIBAABNQAECggIGQAFAOIiAA==.Urubaen:BAAANQADCgUIBgABNQAECgYJEAABAAAAAA==.',
Va='Valanoth:BAAANQADCgIIAgAAAA==.Valeene:BAAANQAECgUIDAAAAA==.',
Ve='Veiler:BAABNQAECoEXAAMMAAgKYQUWPQDDAAAGAAUKLga4ngAjAQAMAAUKRAMWPQDDAAAAAA==.Veruca:BAAANQAECgEJAQAAAA==.Veviseron:BAAANQAECgUJDAAAAA==.',
Vi='Vinstalation:BAAANQAECgQIBwAAAA==.',
Vo='Vonbismarck:BAAANQAECgUICAAAAA==.',
Vr='Vritraz:BAABNQAECoEZAAIFAAgK4iL+CAAZAwAFAAgK4iL+CAAZAwAAAA==.',
Wa='Warsonge:BAAANQAECgEJAQAAAA==.',
We='Wendypini:BAABNQAECoEZAAIGAAgK8Q/PRQAjAgAGAAgK8Q/PRQAjAgAAAA==.',
Wh='Whitlock:BAAANQAECgIJAwAAAA==.',
Ya='Yannhal:BAAANQAECgIJAgAAAA==.',
Za='Zangelf:BAAANQABCgYJDwAAAA==.Zangolf:BAAANQABCggJDQAAAA==.',
Zo='Zodiaac:BAAANQAECgYJDgAAAA==.',
Zy='Zy:BAAANQAECgEIAQAAAA==.',
},}
provider.parse = parse

local rawData = provider.data
provider.data = {}
provider.getChunk = getChunkLookup(rawData, 2)

provider.splitId = 0
provider.splitCount = 1
provider.splitType = 'none'

setmetatable(provider.data, {
	__index = function(table, key)
		provider.getChunk(key)
	end,
})

if _G["ArchonTooltip"] and ArchonTooltip.AddProviderV2 then
	ArchonTooltip.AddProviderV2(lookup, provider)
end

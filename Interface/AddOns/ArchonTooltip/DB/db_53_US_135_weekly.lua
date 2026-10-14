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

local lookup = {'Paladin-Retribution','Shaman-Elemental','Priest-Holy','Priest-Shadow','Mage-Arcane','Mage-Frost','Hunter-BeastMastery','DeathKnight-Frost','DeathKnight-Unholy','Druid-Guardian','Unknown-Unknown','Rogue-Assassination','DemonHunter-Havoc','Warlock-Destruction','Paladin-Holy','Warlock-Demonology','Shaman-Restoration','DeathKnight-Blood','Warrior-Arms','DemonHunter-Vengeance','Druid-Restoration','Druid-Balance','Hunter-Marksmanship','Paladin-Protection','Priest-Discipline','Warrior-Fury','Rogue-Subtlety','Monk-Windwalker','Monk-Mistweaver','Shaman-Enhancement','Evoker-Preservation','Warrior-Protection','Evoker-Devastation',}
local provider = {region='US',realm='KirinTor',name='US',type='weekly',zone=53,date='2026-10-13',data={Ac='Achkmed:BAAANQADCggIEQAAAA==.',
Ad='Adelaid:BAAANQAECgEIAQABNQAFFAUICgABAB4VAA==.',
Ae='Aethelle:BAAANQADCggICAAAAA==.',
Ak='Akalon:BAABNQAECn84AAICAAkKyQusawDZAQACAAkKyQusawDZAQAAAA==.',
Al='Alexandrìte:BAAANQADCgcIEQAAAA==.Allfrost:BAAANQAECgEIAQAAAA==.Aluda:BAABNQAECn8bAAMDAAcKWQ5TmQBEAQADAAYK0AxTmQBEAQAEAAUKgxCCPwAuAQAAAA==.',
An='Anùbis:BAAANQADCgIIAgAAAA==.',
Ao='Aoeina:BAABNQAECn8lAAMFAAkKuhZnfQCDAgAFAAkKfxRnfQCDAgAGAAIKvhX4LwB8AAAAAA==.',
Ap='Apollo:BAABNQAECn8dAAIHAAcKxSUkIwAJAwAHAAcKxSUkIwAJAwAAAA==.',
Ar='Arcanelotus:BAAANQADCgIIAwAAAA==.Arctus:BAAANQADCgcIBwAAAA==.Ariaves:BAAANQAECggIEgAAAA==.Arlind:BAAANQAECgMIAwAAAA==.Artemix:BAAANQAECgQIBAAAAA==.Arthara:BAAANQABCgQIBQAAAA==.',
As='Askeral:BAAANQAECgEIAQAAAA==.Astelana:BAABNQAECn8bAAIBAAcK4AVN9AAuAQABAAcK4AVN9AAuAQAAAA==.',
At='Atanatari:BAAANQADCgcIGwABNQAECgcIFwAEAOEFAA==.Athennah:BAAANQADCgQIBAAAAA==.',
Ba='Bassotan:BAAANQAECgcIEwAAAA==.Baticus:BAAANQADCgcIBwAAAA==.',
Be='Beleva:BAAANQAECgIIBQAAAA==.Belias:BAAANQADCgcIBwAAAA==.Bezzaj:BAAANQAECgQIBAABNQAFFAYIGAAFAOQUAA==.',
Bj='Bjornagain:BAAANQAECgUICgAAAA==.Björne:BAAANQADCggIFAAAAA==.',
Bl='Blackendmoon:BAABNQAECn8aAAMIAAYKbAd0agDsAAAIAAYKaAZ0agDsAAAJAAIKdQiNyABXAAAAAA==.Blackløtus:BAAANQAECggIEAAAAA==.Bloodedge:BAAANQAECgYIDwAAAA==.Bloodklaat:BAAANQADCggICAAAAA==.Bloodnight:BAABNQAECn8XAAIBAAkK1w9NrwC7AQABAAkK1w9NrwC7AQAAAA==.Bluebubbles:BAAANQADCggIIQAAAA==.Bluéyes:BAAANQAECgYICQAAAA==.Blvckscvl:BAABNQAECn8jAAIHAAkKYxxrKAD1AgAHAAkKYxxrKAD1AgAAAA==.Blynna:BAAANQADCgYICQAAAA==.',
Br='Brannik:BAAANQAECgYIDQAAAA==.Breña:BAAANQADCggIGAAAAA==.Broadleaf:BAAANQAECgQICAAAAA==.',
Ca='Camiliana:BAAANQADCgUIBQAAAA==.',
Ce='Cellulight:BAABNQAECn8gAAIKAAkK0xeHDQCIAgAKAAkK0xeHDQCIAgAAAA==.',
Ch='Charizard:BAAANQAECgcIGAAAAQ==.Chelais:BAAANQAECggICQABNQABCgIIAgALAAAAAA==.Cherrycola:BAAANQAECgQICQAAAA==.Chobits:BAAANQAECgQIBAAAAA==.',
Co='Coppertopp:BAAANQADCgQJBQAAAA==.Corvany:BAAANQAECgUICwAAAA==.',
Cr='Crawley:BAABNQAECn9RAAIMAAkK4hvmEADzAgAMAAkK4hvmEADzAgAAAA==.Crazalulla:BAAANQADCgcIDgAAAA==.Creeder:BAABNQAECn8fAAIBAAkK1gycqADJAQABAAkK1gycqADJAQAAAA==.Crixus:BAAANQAECgUICgAAAA==.',
Da='Dagoland:BAAANQADCggIBQAAAA==.Dainty:BAAANQAECgEIAQABNQAFFAYIEAAHAJUYAA==.',
De='Deaanor:BAAANQAECgMIBAAAAA==.Deathcòw:BAAANQAECgYICwAAAA==.Deween:BAAANQAECgYIDwAAAA==.',
Di='Dionysuz:BAAANQAECgcIDQAAAA==.Disdekay:BAAANQAECgMIAgABNQAECgcICwALAAAAAA==.',
Do='Dojoro:BAAANQAECgUIEAAAAA==.Dorc:BAAANQADCgMIAwAAAA==.Dotsarelocks:BAAANQAECgQICgAAAA==.',
Dr='Dradyos:BAAANQAECgUICQAAAA==.Draegare:BAAANQAFFAEIAQAAAA==.Drdeer:BAAANQADCgUIBgAAAA==.',
Ee='Eelecurb:BAAANQADCggIDwAAAA==.',
Ei='Eisysae:BAAANQABCgIJAwAAAA==.',
El='Eliard:BAAANQABCggICQAAAA==.Ellå:BAAANQADCgUIBQABNQAECgkJNAADAPweAA==.',
Er='Erisynn:BAEANQADCgUIBQABNQAFFAQIBwANAJkDAA==.',
Et='Eternalx:BAAANQAECgEIAQAAAA==.',
Ev='Evang:BAABNQAECn8YAAIHAAcKiwoxqwCqAQAHAAcKiwoxqwCqAQAAAA==.Everd:BAAANQAECgYIEwAAAA==.',
Fi='Fiametta:BAABNQAECn8eAAIOAAcKDBe4DAArAgAOAAcKDBe4DAArAgAAAA==.Firerain:BAAANQADCggIEQAAAA==.',
Fl='Flameward:BAAANQADCgYIBgAAAA==.',
Fo='Forkingidiot:BAAANQAECgQIBAAAAA==.Forodin:BAAANQADCgYIBgABNQADCggIFAALAAAAAA==.Foxymizzy:BAAANQAECgQIBAABNQAECgkJIAAPAGsdAA==.',
Fr='Freadrick:BAAANQADCgEIAQABNQADCggIFAALAAAAAA==.Frostknight:BAAANQAECgUIBwAAAA==.',
Fu='Funsize:BAABNQAECn80AAIDAAkK/B5eGgAIAwADAAkK/B5eGgAIAwAAAA==.Furyfangd:BAAANQADCgYIBwAAAA==.',
Ga='Gazzlok:BAAANQADCggIDgAAAA==.',
Ge='Gesen:BAAANQADCggIFQAAAA==.',
Gl='Gloriance:BAABNQAECn8YAAIQAAcKqRbHgQDdAQAQAAcKqRbHgQDdAQAAAA==.',
Go='Gondra:BAAANQABCgIIBAABNQAECgUICwALAAAAAA==.Gortalon:BAAANQABCgIIAgAAAA==.',
Ha='Haplo:BAAANQAECgIIBAAAAA==.',
He='Hellmet:BAAANQAECgIJAgAAAQ==.Hey:BAACNQAFFH8FAAMCAAMKvgI2HgC/AAACAAMKvgI2HgC/AAARAAEKaRaMLQA9AAA1AAQKfyQAAxEACQpLIEUfAOwCABEACQpLIEUfAOwCAAIABQoiB1bKAPoAAAAA.',
Hi='Hinamori:BAAANQAECgMIAwAAAA==.',
Ho='Holythot:BAAANQAECgIIAwABNQAFFAQIDwASANwfAA==.',
Hu='Huogmi:BAAANQAECgQIBQAAAA==.',
Il='Ilharra:BAAANQAECgMIBQAAAA==.Ilililili:BAAANQAECgIIBAAAAA==.Illee:BAAANQAECgcIEQAAAA==.',
Im='Impgangpimp:BAEBNQAECn8eAAIQAAgKPhxkRACCAgAQAAgKPhxkRACCAgAAAA==.Imturtle:BAABNQAECn8oAAISAAgKjiAZFwDyAgASAAgKjiAZFwDyAgABNQAECgkJLQAQANQaAA==.',
Ir='Irmis:BAAANQAECgUIDAAAAA==.',
Iu='Iupiter:BAAANQAECggICQAAAA==.',
Iy='Iyahlieairia:BAAANQAECgMIBAAAAA==.',
Iz='Izabeth:BAABNQAECn8bAAMGAAcKyw3fEQCFAQAGAAcKyw3fEQCFAQAFAAEKQgKG0QErAAAAAA==.',
Ja='Jamella:BAABNQAECn8kAAMBAAgK4hWPlgDyAQABAAcKQxiPlgDyAQAPAAgKjQpeegCmAQAAAA==.',
Je='Jesüschrist:BAAANQAECgEIAQAAAA==.',
Ji='Jiglestd:BAAANQADCgYICAAAAA==.',
Ju='Judeath:BAAANQABCggICQABNQADCggIGAALAAAAAA==.',
Ka='Kabocha:BAAANQAECgcIDgAAAA==.Katsa:BAAANQADCgQIBgAAAA==.Kawi:BAAANQABCgIIAwAAAA==.Kayeh:BAAANQADCgIIAgAAAA==.',
Ki='Kiraneem:BAABNQAECn8hAAIHAAcKNR5VYABUAgAHAAcKNR5VYABUAgAAAA==.Kittie:BAABNQAECn8tAAIRAAkKhxbTRQBHAgARAAkKhxbTRQBHAgAAAA==.Kittynip:BAAANQADCgQIBAABNQAECgQIBAALAAAAAA==.',
Kr='Krinj:BAABNQAECn8fAAMIAAkKXh3vHgCQAgAIAAkKXh3vHgCQAgAJAAEKOQuK3QA0AAAAAA==.Kristov:BAAANQAECgYIBgAAAA==.',
Kt='Ktariani:BAAANQADCgUIBQAAAA==.',
Ky='Kyarla:BAAANQAECgUIDAAAAA==.Kyden:BAAANQADCgEIAQAAAA==.',
La='Lazulie:BAAANQADCgcIBwAAAA==.',
Le='Leahim:BAABNQAECn9bAAISAAkK7SLuBgCIAwASAAkK7SLuBgCIAwAAAA==.Ledani:BAABNQAECn8gAAMDAAYKGRziawDWAQADAAYKGRziawDWAQAEAAQKQQr5TQDYAAAAAA==.Leonato:BAAANQADCgEIAQAAAA==.',
Li='Lilbulky:BAAANQAECgUIBQABNQAECgcIFgATANgYAA==.',
Lo='Lohith:BAABNQAECn8fAAIRAAkKDQUDjgBiAQARAAkKDQUDjgBiAQAAAA==.Lonedawg:BAAANQAECgIIBAAAAA==.Lourival:BAAANQAECgQJBAAAAA==.Lovécoil:BAAANQAECgcIDQAAAA==.',
Lu='Lunâ:BAAANQAECgYJEgAAAA==.',
['Lë']='Lëw:BAAANQAECgYICAAAAA==.',
Ma='Maggnolya:BAAANQAECgQIBAAAAA==.Marsyx:BAABNQAECn8fAAIDAAkKvRsgKgC+AgADAAkKvRsgKgC+AgAAAA==.Matidan:BAAANQAECgYIEwAAAA==.Mayael:BAABNQAECn8lAAMJAAkKrRq4LAB/AgAJAAkKrRq4LAB/AgAIAAcKuA+rTgBzAQAAAA==.',
Me='Medreaux:BAABNQAECn9dAAMDAAkK8iJFBgCTAwADAAkK8iJFBgCTAwAEAAEKdgDslgACAAAAAA==.Merrei:BAABNQAECn8ZAAMNAAgKFhQuMwANAgANAAgKFhQuMwANAgAUAAYKHwkpGAAqAQAAAA==.Meta:BAAANQADCggICAABNQAECgkJHwASABcVAA==.Metalknyte:BAABNQAECn8hAAISAAcKzRJUUACwAQASAAcKzRJUUACwAQAAAA==.',
Mi='Miniknyte:BAABNQAECn8jAAMVAAgKIBPyJwDcAQAVAAgKIBPyJwDcAQAWAAEKAAAXxwAZAAAAAA==.',
Mo='Mohu:BAAANQADCgcIBwAAAA==.Monkey:BAAANQADCgcICgAAAA==.Moonsz:BAAANQADCggILwAAAA==.Mooseonloose:BAAANQAECggIDAAAAA==.Morandus:BAAANQAECgEIAQAAAA==.Moraria:BAAANQADCgMIAwAAAA==.Morgrathh:BAAANQADCgYIBgAAAA==.',
My='Mychelle:BAABNQAECn8eAAIXAAYKlgwZQQBHAQAXAAYKlgwZQQBHAQAAAA==.',
Na='Nakryn:BAAANQAECgcIEQAAAA==.Naryeth:BAAANQADCgEIAQAAAA==.Natorn:BAABNQAECn8fAAITAAkKeCElJAAmAwATAAkKeCElJAAmAwAAAA==.Nay:BAAANQAECgcJCQAAAA==.',
Ne='Nemrod:BAAANQAECgEIAQAAAA==.Nezum:BAAANQAECgEIAQAAAA==.',
Ni='Nickoli:BAAANQAECgEIAQAAAA==.Niterend:BAABNQAECn8WAAITAAcK2BjXfAAfAgATAAcK2BjXfAAfAgAAAA==.',
No='Nojomoto:BAAANQADCgcIBwAAAA==.Norabel:BAAANQADCgQICAAAAA==.',
['Nø']='Nøxxi:BAABNQAECn8gAAIOAAcKpBtaCgBQAgAOAAcKpBtaCgBQAgAAAA==.',
Ob='Obbimcanood:BAAANQADCgIIAgAAAA==.',
Ok='Okbloomer:BAAANQAECgcIDgABNQAFFAYIEAADAJ4YAA==.',
Ol='Oldben:BAABNQAECn8hAAMBAAcKmBCl1QBpAQABAAcKmBCl1QBpAQAYAAMK5gCAagA7AAAAAA==.',
Or='Oriel:BAABNQAECn8hAAIZAAcKcAfPEAAaAQAZAAcKcAfPEAAaAQAAAA==.',
Ov='Ovy:BAAANQAECgEIAQAAAA==.',
Pa='Paleblueeye:BAAANQADCgIIAgAAAA==.Panda:BAAANQAECgMIAwAAAA==.',
Pi='Pixystix:BAAANQADCgYIDAABNQAECgYIHgAXAJYMAA==.',
Pl='Plop:BAAANQAECgQIBAABNQAECggIEgALAAAAAA==.Plumpcheeks:BAAANQADCggIDQAAAA==.',
Po='Poc:BAAANQAECgYIEQAAAA==.Poundya:BAAANQADCgYICgAAAA==.',
Pr='Prinsana:BAABNQAECn8hAAIYAAcKchSYJAC4AQAYAAcKchSYJAC4AQAAAA==.',
Pu='Purquis:BAAANQAECgYICQAAAA==.',
Ra='Raeve:BAAANQADCgYIBgAAAA==.Raidkicker:BAAANQADCgEIAQABNQAECgQICgALAAAAAA==.',
Re='Reaperlord:BAABNQAECn8bAAIPAAcK5BwlQwBWAgAPAAcK5BwlQwBWAgAAAA==.',
Ri='Rizzardofoz:BAAANQADCgMIAwAAAA==.',
Rl='Rllybuffnerd:BAAANQAECggICQAAAA==.',
Ro='Rodikus:BAABNQAECn8qAAMDAAkKzhqOHwDvAgADAAkKzhqOHwDvAgAEAAEKAACsbABOAAAAAA==.',
Sa='Saiaa:BAABNQAECn8gAAIMAAcKIwa/WQBKAQAMAAcKIwa/WQBKAQAAAA==.Sakeena:BAAANQAECgIIBAAAAA==.Samará:BAAANQADCgQICAAAAA==.Sarleigh:BAAANQADCgIIAgAAAA==.Sattia:BAAANQAECgUJDQAAAA==.',
Sh='Shadereaver:BAAANQAECggICAAAAA==.Shenanygins:BAAANQADCgMIAwAAAA==.Shendalla:BAAANQABCgQIBAAAAA==.Shinokishi:BAAANQAECgYIEwAAAA==.',
Si='Silentninjaa:BAABNQAECn8kAAIaAAcKew/vDwCmAQAaAAcKew/vDwCmAQAAAA==.Simphunter:BAEANQAECgcIEwABNQAECggIHgAQAD4cAA==.Sinfel:BAAANQAECgUIEAAAAA==.Sit:BAAANQADCggICAAAAA==.',
Sk='Skoriavis:BAAANQAECgEIAQABNQAECgcIHQAbADUZAA==.Skoriko:BAABNQAECn8dAAMbAAcKNRm8FgAoAgAbAAcKNRm8FgAoAgAMAAMK2gxjgwCaAAAAAA==.',
So='Sonett:BAAANQAECgIIBAAAAA==.Sonto:BAAANQAECgQICAAAAA==.',
Sp='Sparks:BAAANQADCgYIBgAAAA==.Splunk:BAABNQAECn8fAAISAAkKFxUfOAAlAgASAAkKFxUfOAAlAgAAAA==.',
St='Staggerdaddy:BAAANQAECgQIBgAAAA==.Stariya:BAAANQAECgIIBAAAAA==.Stompinghoof:BAAANQAECgYICAAAAA==.Strapattack:BAAANQADCgcIBwAAAA==.Strawyà:BAABNQAECn8YAAMcAAcK4wsWNwBWAQAcAAcK4wsWNwBWAQAdAAEKWAXuTwAnAAAAAA==.',
Sy='Syannara:BAAANQAECgQIBAAAAA==.Syklar:BAAANQADCgEIAQAAAA==.Syssa:BAAANQAECgQIDQABNQAECgUICgALAAAAAA==.',
['Sì']='Sìrocco:BAAANQAECgUIBwAAAA==.',
Ta='Taleranor:BAAANQADCggIHwAAAA==.Tamerizer:BAABNQAECn8fAAIXAAgK8BCRLwDNAQAXAAgK8BCRLwDNAQAAAA==.',
Te='Tearali:BAAANQADCggICAAAAA==.Teejrath:BAABNQAECn8VAAQJAAkK6w7cWgChAQAJAAgKmw/cWgChAQAIAAEKzgoPsQArAAASAAEKAABG3gAeAAAAAA==.Teekeez:BAAANQADCggICQAAAA==.',
Th='Thekal:BAAANQADCgEIAgAAAA==.Theodorel:BAAANQAECgEIAQAAAA==.Thicchick:BAAANQAECgUICwAAAA==.Thirge:BAAANQAECgUIEAAAAA==.Thorek:BAAANQADCgcIBwAAAA==.Thrushbeard:BAAANQADCgcIBwAAAA==.Thundertaco:BAAANQAECgUIEAAAAA==.',
Ti='Tighten:BAAANQABCgEIAQAAAA==.',
To='Toesniffer:BAAANQADCggICAAAAA==.Tofaaway:BAAANQAECgIIBAAAAA==.Tolak:BAAANQAECgUIDgAAAA==.Tormikinos:BAABNQAECn8YAAIWAAcKcAkXXwBQAQAWAAcKcAkXXwBQAQAAAA==.Torturousôwl:BAAANQAECgUIEAAAAA==.Totemknyte:BAAANQABCgUIBQABNQAECgcIIQASAM0SAA==.',
Tr='Trillianh:BAAANQADCgEIAQAAAA==.Trisky:BAABNQAECn8jAAMPAAgKNh2lNACPAgAPAAgKNh2lNACPAgAYAAEKMw8hdAAnAAAAAA==.',
Tu='Tumblebumble:BAAANQADCgMIAwAAAA==.Turtle:BAABNQAECn8tAAMQAAkK1BpZTgBmAgAQAAgKDxlZTgBmAgAOAAIKehMMTwCRAAAAAA==.',
Un='Unholyghost:BAAANQABCgUICgAAAA==.',
Va='Vadrakquin:BAAANQAECggIDwAAAA==.Valshamommy:BAABNQAECn8dAAIeAAgKDRJgEwAvAgAeAAgKDRJgEwAvAgAAAA==.Vanloth:BAAANQADCgEIAgAAAA==.Vantadim:BAAANQADCgMIAwAAAA==.',
Ve='Vegito:BAAANQAECgIIBQAAAA==.Velfurry:BAAANQAECgEIAQABNQAFFAcIIgAfALoNAA==.Verlassan:BAAANQADCgcIBwAAAA==.',
Vi='Viverrid:BAAANQAECgEIAQAAAA==.',
Vo='Voin:BAACNQAFFH8FAAIgAAIKyBVBBgCEAAAgAAIKyBVBBgCEAAA1AAQKfzIAAiAACQq/JJoBALIDACAACQq/JJoBALIDAAAA.Vorpine:BAABNQAECn8hAAMEAAcKZBB0LQC2AQAEAAcKZBB0LQC2AQADAAcKvRGeggCLAQAAAA==.',
We='Wetkittie:BAAANQADCgYIBwAAAA==.',
Wi='Wiccawitch:BAAANQADCgYIEwAAAA==.Wirhl:BAAANQAECgQIDQAAAA==.',
Wo='Worthatry:BAABNQAECn8kAAIBAAkKVyA9KwAYAwABAAkKVyA9KwAYAwAAAA==.',
Xa='Xalbit:BAABNQAECn8fAAIRAAcKuAMjtwD5AAARAAcKuAMjtwD5AAAAAA==.Xantia:BAABNQAECn8qAAIVAAkK5g8eJgDuAQAVAAkK5g8eJgDuAQAAAA==.',
Xe='Xenlo:BAAANQAECgYICgAAAA==.',
Yo='Yogurt:BAAANQADCgMJAwABNQAECgIJAgALAAAAAA==.',
Za='Zaizel:BAAANQAECgEIAQABNQAFFAYIDwAhAMoSAA==.Zalulu:BAAANQAECgMIAwABNQAECgQIBwALAAAAAA==.Zathennyx:BAAANQAECgMIAwAAAA==.',
Ze='Zenpai:BAAANQAECgUICwAAAA==.',
Zv='Zvorunalotus:BAAANQADCgYIDQAAAA==.',
['Ðr']='Ðread:BAAANQAECgUICAAAAA==.',
['ßß']='ßßqñüt:BAAANQAECgUIEwAAAA==.',
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

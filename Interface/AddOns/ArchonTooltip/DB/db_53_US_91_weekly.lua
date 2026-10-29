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

local lookup = {'Druid-Balance','Shaman-Elemental','Unknown-Unknown','Monk-Mistweaver','Monk-Windwalker','Priest-Holy','Evoker-Augmentation','DemonHunter-Devourer','Hunter-BeastMastery','Hunter-Marksmanship','DeathKnight-Unholy','DemonHunter-Havoc','Warlock-Destruction','Priest-Shadow','Paladin-Protection','Warrior-Fury','Warrior-Arms','Shaman-Restoration','Paladin-Retribution','Rogue-Assassination','Hunter-Survival','Druid-Restoration','Warrior-Protection','Evoker-Devastation','Evoker-Preservation','DeathKnight-Blood','Warlock-Demonology','Druid-Feral','Rogue-Outlaw','Mage-Arcane','Mage-Frost','Druid-Guardian','Paladin-Holy','Rogue-Subtlety','Warlock-Affliction','Priest-Discipline',}
local provider = {region='US',realm='Executus',name='US',type='weekly',zone=53,date='2026-10-27',data={Al='Alodiar:BAAANQADCgUICQAAAA==.',
An='Andersen:BAAANQADCgEIAQAAAA==.Andryu:BAABNQAECn81AAIBAAoKqBJ+GQDGAQABAAoKqBJ+GQDGAQAAAA==.Annde:BAABNQAECn8vAAICAAoKIxiSOQCQAgACAAoKIxiSOQCQAgAAAA==.Anyana:BAAANQADCgQIBAABNQAECgQJBQADAAAAAA==.',
Ar='Ardre:BAAANQADCgUIBQABNQADCgUICQADAAAAAA==.Artemus:BAACNQAFFH8LAAMEAAYKMAlSBgAsAQAEAAUK1gNSBgAsAQAFAAQKaAPhDgCcAAA1AAQKfzMAAwQACgq1HeoJAOoCAAQACgq1HeoJAOoCAAUABwqODoQ0AHEBAAE1AAQKBQgHAAMAAAAA.Arïel:BAAANQAECgUIDQAAAA==.',
Be='Beeftoteeth:BAAANQAECgUICgAAAA==.Ber:BAABNQAECn8lAAIGAAoK0xknDgAHAwAGAAoK0xknDgAHAwABNQAFFAUIDQAHAJcLAA==.Bexxy:BAAANQAECgUIDAAAAA==.',
Bi='Bibicrits:BAAANQAECgEIAQABNQAECgoKOgAIAE8eAA==.',
Bl='Blueseno:BAAANQADCgYIBgAAAA==.',
Bo='Bouras:BAAANQAECgYIEgAAAA==.',
Br='Broadfang:BAACNQAFFH8gAAMJAAcKDhohBwAkAQAKAAYKrhTzBwDLAQAJAAYK+RohBwAkAQA1AAQKfz8AAwoACgoyIp4UALoCAAoACQrnIZ4UALoCAAkABgoVInY6APcBAAAA.',
Bu='Bubbleoseven:BAAANQAECgYICQAAAA==.Bullorly:BAACNQAFFH8KAAILAAUK3B3YBADeAQALAAUK3B3YBADeAQA1AAQKfzAAAgsACgqTJHUFAKEDAAsACgqTJHUFAKEDAAAA.',
Ca='Catirus:BAAANQADCgYICAAAAA==.',
Ch='Chareddh:BAAANQADCgMIAwABNQAECgoKPgAEAHocAA==.Cheehoo:BAAANQADCgQIBAAAAA==.Chunt:BAAANQADCgcIBwAAAA==.',
Cl='Cleo:BAABNQAECn8WAAMMAAcKWAEkfQCCAAAMAAcKWAEkfQCCAAAIAAUK7QAiYwBeAAAAAA==.Clipe:BAABNQAECn8WAAINAAoK4xIeCAB+AgANAAoK4xIeCAB+AgAAAA==.Clipee:BAAANQADCgEIAQAAAA==.Clipeskeg:BAAANQAECgEIAQAAAA==.Clipex:BAAANQADCgMIAwAAAA==.Clipey:BAAANQADCggIDgAAAA==.',
Co='Coldsnap:BAAANQADCgQIBgAAAA==.Connor:BAAANQADCgYICgAAAA==.Control:BAAANQAECgMIBgAAAA==.',
Cr='Crimsonpaw:BAAANQAECgYIBgAAAA==.Crispicrits:BAAANQAECggIEgABNQAFFAQIBQAGAF4UAA==.',
Cy='Cynîc:BAAANQAECgMIBgAAAA==.',
Da='Dalaran:BAABNQAECn8/AAIIAAoKJgzeFwB6AQAIAAoKJgzeFwB6AQAAAA==.Darenas:BAACNQAFFH8MAAIOAAYKAxD5CQBeAQAOAAYKAxD5CQBeAQA1AAQKfzoAAg4ACgpgHV4OAAkDAA4ACgpgHV4OAAkDAAAA.Darkwing:BAAANQAECgEIAQABNQAECgYIGAAPAGQOAA==.',
De='Deathbooze:BAABNQAECn8nAAILAAkKsCEYGgDwAgALAAkKsCEYGgDwAgAAAA==.Deathmikee:BAABNQAECn80AAILAAoKDSJiEAA0AwALAAoKDSJiEAA0AwAAAA==.Delilah:BAAANQAECgYIDwAAAA==.Delita:BAAANQAECgMIAwAAAA==.Demonea:BAAANQAECgEIAQAAAA==.Denari:BAAANQADCgcIBwABNQAECgoKPgABAOkVAA==.Derek:BAAANQAECgUICAAAAA==.',
Dr='Drakkenbreth:BAAANQAECgQIBAAAAA==.Drakos:BAAANQADCggIEAAAAA==.',
Du='Durton:BAABNQAECn85AAMQAAoKUR8YAgDGAgAQAAoKUR8YAgDGAgARAAMK6wuQGAGrAAAAAA==.',
Ec='Echø:BAAANQADCgUIBQAAAA==.',
Ed='Edrency:BAAANQADCgYIBgAAAA==.',
Ef='Eferis:BAAANQAECggICAAAAA==.',
El='Elderdorje:BAABNQAECn8+AAMEAAoKehwzBQDVAgAEAAoKehwzBQDVAgAFAAcKUAVDRwDlAAAAAA==.Elixe:BAAANQAECgEIAgAAAA==.Elmersglue:BAAANQAECgEIAQAAAA==.Elondre:BAABNQAECn9DAAISAAoKkiJOAgDXAwASAAoKkiJOAgDXAwAAAA==.',
Ev='Evangeliné:BAAANQAECgUIBQABNQAECgoKNAAGACERAA==.',
Ex='Execfive:BAAANQADCgIIAQAAAA==.',
Fe='Femboi:BAABNQAECn86AAIIAAoKTx5YCgA1AwAIAAoKTx5YCgA1AwAAAA==.',
Fi='Firecracker:BAAANQAECgYIDwAAAA==.',
Fo='Fortwooh:BAAANQADCgcIEwAAAA==.',
Fr='Freshlight:BAAANQAECgUIDgABNQAFFAQICgAEANIRAA==.',
Fu='Fuurak:BAAANQAFFAEIAQAAAA==.',
Ga='Gado:BAAANQAECgQIBQABNQAFFAUIDQAHAJcLAA==.Galatea:BAACNQAFFH8JAAITAAMK1RICDQDdAAATAAMK1RICDQDdAAA1AAQKf08AAhMACgpDIkAvAAwDABMACgpDIkAvAAwDAAAA.Galifen:BAABNQAECn9CAAIBAAoKMibBAQDjAwABAAoKMibBAQDjAwAAAA==.Gameplan:BAAANQADCgYICAAAAA==.Gank:BAABNQAECn8uAAIUAAoKoSKuBACLAwAUAAoKoSKuBACLAwAAAA==.Gardener:BAAANQABCgIIBAAAAA==.',
Gh='Ghreen:BAAANQAECgYICQAAAA==.',
Gi='Gigathreat:BAAANQAECgEIAgAAAA==.Gilgahmesh:BAABNQAECn8YAAIPAAYKZA71NAA9AQAPAAYKZA71NAA9AQAAAA==.',
Gn='Gnomegrown:BAABNQAECn8aAAIBAAcKigtyNgDxAAABAAcKigtyNgDxAAAAAA==.',
Go='Gothika:BAAANQADCgIIAgAAAA==.Goy:BAAANQAECgcIAgAAAA==.',
Gr='Grainbelt:BAAANQAECggIDgAAAA==.',
Gy='Gyrux:BAAANQAECgEIBAAAAA==.',
Ha='Halyer:BAAANQADCggIGQAAAA==.Hamalainen:BAABNQAECn8bAAMVAAkKChADCQC0AQAVAAYKyBMDCQC0AQAJAAkKYQqD0QBeAQABNQAFFAQICgAEANIRAA==.Harrydresden:BAAANQABCgIIBAAAAA==.Havøc:BAAANQAECgMIBAAAAA==.',
He='Helioboops:BAAANQADCggIEQAAAA==.',
Ho='Hobbz:BAACNQAFFH8MAAITAAYK+hQDDgBrAQATAAYK+hQDDgBrAQA1AAQKfzkAAhMACgq/JOkNAAYDABMACgq/JOkNAAYDAAAA.',
Il='Illandros:BAABNQAECn8eAAIOAAYKCw88PABIAQAOAAYKCw88PABIAQAAAA==.',
In='Inspire:BAACNQAFFH8NAAIWAAUKEhWhBwCBAQAWAAUKEhWhBwCBAQA1AAQKfysAAhYACgqOImcJAC8DABYACgqOImcJAC8DAAAA.',
Is='Isinia:BAAANQADCgEIAQAAAA==.Isira:BAAANQAECgcICQAAAA==.',
Ja='Jaína:BAAANQAECgIIBgABNQAECgYIEgADAAAAAA==.',
Jc='Jcvd:BAAANQADCgYICwABNQAFFAQICgAEANIRAA==.',
Je='Jelina:BAAANQAECgYIDgAAAA==.',
Ji='Jiren:BAACNQAFFH8KAAIEAAQK0hHpAwASAQAEAAQK0hHpAwASAQA1AAQKfzgAAwQACgpKIMAJAO4CAAQACgpKIMAJAO4CAAUAAgqMBI9PABoAAAAA.',
Jo='Johnson:BAABNQAECn8XAAIXAAgK2BWIEQAOAgAXAAgK2BWIEQAOAgAAAA==.Joran:BAABNQAECn8XAAITAAYKqQnA+QArAQATAAYKqQnA+QArAQAAAA==.',
Kr='Kro:BAAANQAECgEIAwAAAA==.',
La='Laststop:BAAANQADCgYIBQAAAA==.',
Le='Leanea:BAAANQAECgIIAwAAAA==.',
Li='Liera:BAABNQAECn8bAAILAAgKWRElJwBBAQALAAgKWRElJwBBAQAAAA==.Lightsac:BAAANQADCgYIBwAAAA==.Limmywinks:BAAANQAECgIIAgAAAA==.',
Ll='Lloydlei:BAAANQAECgcIEAAAAA==.',
Lu='Luminå:BAABNQAECn8rAAINAAoK9BttBADkAgANAAoK9BttBADkAgAAAA==.',
Ma='Maibisan:BAABNQAECn9cAAMMAAoKDyY4AQDsAwAMAAoKDyY4AQDsAwAIAAgKBSJCHgBfAgAAAA==.Malificent:BAAANQAECgMIBAAAAA==.',
Me='Metaevoker:BAABNQAECn9GAAIYAAoKYRu7AwBQAgAYAAoKYRu7AwBQAgAAAA==.',
Mo='Monawah:BAABNQAECn8hAAIJAAgKFAv5jADwAQAJAAgKFAv5jADwAQAAAA==.Mookong:BAAANQADCgYIBwABNQAECgQIBAADAAAAAA==.Moonsliver:BAAANQAECgQICwAAAA==.Moorf:BAABNQAECn8cAAMSAAkKfA4WSAB1AQASAAgKQhAWSAB1AQACAAEKAACPZAEPAAAAAA==.Morff:BAABNQAECn8WAAIYAAcKEwv/HwBWAQAYAAcKEwv/HwBWAQAAAA==.Motleychew:BAAANQAECgEIAQAAAA==.',
My='Mystwolf:BAAANQAECgUJCgAAAA==.',
Ne='Ned:BAAANQADCgMIAwABNQAECgYIEwADAAAAAA==.',
Ni='Nightember:BAAANQAECgEIAQABNQAECgoKPgAEAHocAA==.Nightski:BAABNQAECn8bAAIWAAcKjxkPFADoAQAWAAcKjxkPFADoAQAAAA==.Nizzari:BAAANQAECgMIBgABNQAFFAUIDQAHAJcLAA==.',
No='Nobuseri:BAAANQAECgcIDAAAAA==.Nothalyer:BAABNQAECn86AAIZAAoKuQdaEQBUAQAZAAoKuQdaEQBUAQAAAA==.',
['Nå']='Nåtrii:BAAANQADCggICAABNQAECggIGgAZAJ4IAA==.',
Ob='Obliviora:BAAANQADCgYIBgAAAA==.',
Og='Ogdi:BAAANQAECgYIEwAAAA==.',
Ol='Olaria:BAAANQADCgMIAwAAAA==.',
Oo='Ookook:BAAANQAECggICAABNQAECgoKFAAaANANAA==.',
Or='Orwasitgarp:BAAANQADCgYIBgABNQAECgUICwADAAAAAA==.Orwasitme:BAAANQAECgUICwAAAA==.Orwasitmii:BAAANQADCgMJAwABNQAECgUICwADAAAAAA==.',
Pa='Paladinii:BAAANQAECgUIBgAAAA==.',
Ph='Philonk:BAABNQAECn8fAAIFAAkKgRC6JgDtAQAFAAkKgRC6JgDtAQAAAA==.',
Pj='Pjxyo:BAAANQAECgYIEwAAAA==.',
Po='Polytots:BAACNQAFFH8RAAMSAAYKFg7RDgBiAQASAAYKFg7RDgBiAQACAAIKcwkNJwCQAAA1AAQKf0YAAxIACgreJP4BAMgDABIACgreJP4BAMgDAAIAAwpIEG2bAGoAAAAA.',
Ps='Psycototem:BAAANQAECgMICAAAAA==.',
Ra='Razering:BAAANQAECgEIAwAAAA==.Razius:BAAANQAECggIDwAAAA==.',
Re='Rebexha:BAABNQAECn8ZAAMNAAYKUwreQgC5AAANAAQKCwjeQgC5AAAbAAYKeQfknQC0AAAAAA==.Replayjade:BAAANQADCgEIAQAAAA==.',
Ri='Ricklepick:BAABNQAECn8WAAMWAAkK5R3MBwDZAgAWAAkK5R3MBwDZAgAcAAEKAAA1QAA6AAABNQAFFAQICgAEANIRAA==.',
Ro='Romaeus:BAAANQADCgYIBwAAAA==.',
Ru='Ruskie:BAAANQADCgEIAQAAAA==.',
Ry='Ryzenther:BAAANQAECgIJBAAAAA==.',
['Rà']='Ràgnar:BAAANQAECgMIAgAAAA==.Ràgñar:BAAANQADCgYIEQAAAA==.',
Sa='Sanctis:BAAANQADCgYIBgAAAA==.',
Sc='Scarpa:BAAANQAECgEIAQABNQAECgoKPgABAOkVAA==.Scathclipe:BAABNQAECn8nAAMUAAkKQxaELgAqAgAUAAkKrxKELgAqAgAdAAgKvxT/CAAEAgAAAA==.',
Se='Sealedfate:BAAANQAECgEIAgAAAA==.Seancodi:BAAANQAECgEIAQABNQAFFAYIFQAIAPIdAA==.Senomage:BAABNQAECn8nAAMeAAoKcyJbNgAcAwAeAAoKcyJbNgAcAwAfAAMK/R35HwDqAAAAAA==.Serphentos:BAAANQABCgIIAgAAAA==.',
Sh='Shasato:BAABNQAECn8vAAMgAAoKix8HBgAzAwAgAAoKix8HBgAzAwABAAQKVAzCSgCaAAAAAA==.Shazrast:BAAANQADCgQIBAAAAA==.Shockss:BAAANQAECgYIDgAAAA==.',
Si='Sidie:BAAANQADCgMIAwAAAA==.Sindora:BAAANQADCgEIAQAAAA==.Sizouze:BAABNQAECn81AAIGAAoKvw8nOADXAQAGAAoKvw8nOADXAQAAAA==.',
Sk='Skyepic:BAACNQAFFH8jAAMhAAgKixqXAgCAAgAhAAgKixqXAgCAAgAPAAEKTgWlEQA+AAA1AAQKfyYAAiEACQp+JhQBAOMDACEACQp+JhQBAOMDAAAA.Skylight:BAAANQAECggIDAAAAA==.',
Sn='Sneakfu:BAABNQAECn8yAAMUAAkKNxVOGwAjAQAiAAkKRhScHQDmAQAUAAgKjxBOGwAjAQAAAA==.Snugwalnut:BAACNQAFFH8RAAISAAcKtg7gCADDAQASAAcKtg7gCADDAQA1AAQKfy8AAhIACgqkH4g0AI0CABIACgqkH4g0AI0CAAAA.',
So='Soejoedi:BAABNQAECn8+AAIBAAoK6RWtFQD4AQABAAoK6RWtFQD4AQAAAA==.Sorrowin:BAAANQABCgIIAgAAAA==.',
Sp='Spicyburrito:BAAANQAECgIIAgAAAA==.',
St='Stitchzpls:BAAANQAECgIIBQAAAA==.',
Su='Sunraku:BAAANQABCgIIAgAAAA==.',
Ta='Taintedrush:BAACNQAFFH8LAAIjAAUKhArpAADgAAAjAAUKhArpAADgAAA1AAQKfzYAAiMACgrHGhwDANMCACMACgrHGhwDANMCAAAA.Tarhostamir:BAAANQAECgUIBgAAAA==.Taurup:BAAANQADCgYIEAABNQAFFAUIDQAHAJcLAA==.Tazz:BAABNQAECn8hAAMJAAgK3APxpwDeAAAJAAgK3APxpwDeAAAKAAEKAABwoAAaAAAAAA==.',
Te='Teenjus:BAAANQADCggIDQAAAA==.',
Th='Thaluus:BAAANQADCgUICQAAAA==.Thanossnap:BAAANQABCgQIBgABNQAECgoKPgAEAHocAA==.Thaysinga:BAABNQAECn8uAAILAAkKHBQCHgCEAQALAAkKHBQCHgCEAQAAAA==.Thelandlord:BAAANQAECgIIAwAAAA==.Thunderblast:BAABNQAECn8YAAIRAAYKxhi3tACZAQARAAYKxhi3tACZAQAAAA==.Thuss:BAAANQADCgQIBAAAAA==.',
To='Totemtosser:BAAANQAECgEIAQAAAA==.',
Tr='Trollor:BAAANQAECgEIAgAAAA==.',
Ut='Utzon:BAAANQAECgEIAQABNQAECgoKPgABAOkVAA==.',
Va='Vaedan:BAAANQADCgcIEwAAAA==.Valkyrrie:BAAANQADCgcICAABNQADCggIGQADAAAAAA==.Vander:BAABNQAECn8ZAAMGAAYKkh9JMwDvAQAGAAYKkh9JMwDvAQAOAAEKAABnjwAbAAAAAA==.Vannder:BAAANQAECgEIBQABNQAECgYIGQAGAJIfAA==.Vayper:BAABNQAECn9DAAQOAAoKRiHDBgBsAwAOAAoKRiHDBgBsAwAGAAIK4gop4wB/AAAkAAEK8gRELwAmAAAAAA==.Vaypshawk:BAAANQADCggIFAABNQAECgoKQwAOAEYhAA==.',
['Vë']='Vënöm:BAAANQAECgEIAQABNQAECgoKKwANAPQbAA==.',
Wa='Waggo:BAABNQAECn8hAAICAAcKrBAWgwCdAQACAAcKrBAWgwCdAQAAAA==.Waken:BAAANQAECgcIDAAAAA==.Warm:BAAANQAFFAEIAQAAAA==.Waterboy:BAAANQADCgcIDAABNQADCgUIBgADAAAAAA==.',
We='Weemsy:BAAANQADCgYIBgAAAA==.Wellmet:BAAANQAECgEIAwAAAA==.',
Wi='Wildfire:BAACNQAFFH8KAAIVAAcKDRxFAAA9AgAVAAcKDRxFAAA9AgA1AAQKfzoAAhUACgq5JlIAANQDABUACgq5JlIAANQDAAAA.',
Wo='Wolfhammer:BAABNQAECn86AAIXAAoKtxcJBwD7AQAXAAoKtxcJBwD7AQAAAA==.',
Wr='Wreckadin:BAABNQAECn8dAAITAAoKRB3DQQDPAgATAAoKRB3DQQDPAgAAAA==.',
Ya='Yaztraz:BAABNQAECn8xAAMSAAoKmBwUPwBkAgASAAoKmBwUPwBkAgACAAcKhgzhrgA1AQAAAA==.',
Ye='Yellowflag:BAAANQAECggIEQABNQAFFAgIJgAaAKMgAA==.',
Ym='Ympbeear:BAAANQAECgEIAgAAAA==.',
Za='Zarturion:BAAANQAECgIICAAAAA==.',
Zo='Zod:BAACNQAFFH8NAAMHAAUKlwvVBADIAAAHAAUKlwvVBADIAAAYAAEKQQJCEQAyAAA1AAQKfzcAAwcACgo3GMYEALACAAcACgo3GMYEALACABgABAoQC+grAMUAAAAA.',
['Às']='Àsh:BAABNQAECn8ZAAIGAAoKfhGGXwACAgAGAAoKfhGGXwACAgAAAA==.',
['Év']='Évangeline:BAAANQAECgcIDQABNQAECgoKNAAGACERAA==.',
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

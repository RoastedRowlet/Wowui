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

local lookup = {'Druid-Balance','Shaman-Elemental','Hunter-BeastMastery','Paladin-Holy','Unknown-Unknown','Monk-Mistweaver','Monk-Windwalker','Priest-Holy','Priest-Shadow','Evoker-Augmentation','DemonHunter-Devourer','Hunter-Marksmanship','DeathKnight-Unholy','DemonHunter-Havoc','Warlock-Destruction','Shaman-Restoration','Paladin-Protection','DeathKnight-Blood','Warrior-Fury','Warrior-Arms','Paladin-Retribution','Rogue-Assassination','Hunter-Survival','Druid-Restoration','Warrior-Protection','Evoker-Devastation','Evoker-Preservation','Rogue-Subtlety','Monk-Brewmaster','Warlock-Demonology','Rogue-Outlaw','Mage-Arcane','Mage-Frost','Druid-Guardian','Warlock-Affliction','Priest-Discipline','Shaman-Enhancement',}
local provider = {region='US',realm='Executus',name='US',type='weekly',zone=53,date='2026-11-17',data={Al='Alodiar:BAAANQADCgUICQAAAA==.',
An='Andersen:BAAANQADCgEIAQAAAA==.Andryu:BAABNQAECn9NAAIBAAoKEBXoHgAJAgABAAoKEBXoHgAJAgAAAA==.Annde:BAABNQAECn8zAAICAAoKIxiSOQCQAgACAAoKIxiSOQCQAgAAAA==.Annikya:BAAANQADCgYIBgABNQAECgoKJAADACsFAA==.Anyana:BAAANQADCgQIBAABNQAECgcIGwAEAKocAA==.',
Ar='Ardre:BAAANQADCgUIBQABNQADCgUICQAFAAAAAA==.Artemus:BAACNQAFFH8MAAMGAAcKfwtSBgAsAQAGAAUK1gNSBgAsAQAHAAUKlwPhDgCcAAA1AAQKfzYAAwYACgpcH+oJAOoCAAYACgpcH+oJAOoCAAcABwqODoQ0AHEBAAE1AAQKBggJAAUAAAAA.Arïel:BAABNQAECn8aAAMIAAoKZBHdpwAeAQAIAAcK8BXdpwAeAQAJAAcK2gtXMgD7AAAAAA==.',
Be='Beeftoteeth:BAAANQAECgUIBwAAAA==.Ber:BAABNQAECn87AAIIAAoK7hw9FgAlAwAIAAoK7hw9FgAlAwABNQAFFAUIDQAKAJcLAA==.Bexxy:BAAANQAECgUIDgAAAA==.',
Bi='Bibicrits:BAAANQABCggIDgABNQAECgoKSgALACggAA==.',
Bl='Blueseno:BAAANQADCgYIBgAAAA==.',
Bo='Bouras:BAAANQAECgYIEQAAAA==.',
Br='Broadfang:BAACNQAFFH8iAAMDAAgKXRaxCQBTAQAMAAYKrhTzBwDLAQADAAcKXBaxCQBTAQA1AAQKf1EAAwMACgrIIvElAKcCAAwACQrnIZ4UALoCAAMACAorIPElAKcCAAAA.',
Bu='Bubbleoseven:BAAANQAECgYICAAAAA==.Bullorly:BAACNQAFFH8KAAINAAUK3B3YBADeAQANAAUK3B3YBADeAQA1AAQKf0EAAg0ACgqoJXUFAKEDAA0ACgqoJXUFAKEDAAAA.',
Ca='Catirus:BAAANQADCgYICAAAAA==.',
Ch='Chareddh:BAAANQADCgMIAwABNQAECgoKUgAGAHYeAA==.Cheehoo:BAAANQADCggIBwAAAA==.Chunt:BAAANQADCgcIBwAAAA==.',
Cl='Cleo:BAABNQAECn8WAAMOAAcKWAEkfQCCAAAOAAcKWAEkfQCCAAALAAUK7QAiYwBeAAAAAA==.Clipe:BAABNQAECn8lAAIPAAoKuhuoAQCbAgAPAAoKuhuoAQCbAgAAAA==.Clipee:BAAANQADCgEIAQAAAA==.Clipeskeg:BAAANQADCgEIAQAAAA==.Clipex:BAAANQADCgMIAwAAAA==.Clipey:BAAANQADCggIDgAAAA==.',
Co='Coldsnap:BAAANQADCgQIBgAAAA==.Connor:BAAANQADCgYICgAAAA==.Control:BAAANQAECgMIAwAAAA==.',
Cr='Crimsonpaw:BAAANQAECggICAAAAA==.Crispicrits:BAABNQAECn8iAAMQAAkKXBSlQwAFAgAQAAkKXBSlQwAFAgACAAgKBg/zTwCYAQABNQAFFAUIBwAIAGMSAA==.',
Cy='Cynîc:BAAANQAECgMIBgAAAA==.',
Da='Dalaran:BAABNQAECn9OAAILAAoKVA23HwCkAQALAAoKVA23HwCkAQAAAA==.Darenas:BAACNQAFFH8NAAIJAAcKPQ75CQBeAQAJAAcKPQ75CQBeAQA1AAQKf0YAAgkACgpsHl4OAAkDAAkACgpsHl4OAAkDAAAA.Darkwing:BAAANQABCgIIAQABNQAECgcIKAARANANAA==.',
De='Deathbooze:BAABNQAECn8nAAINAAkKsCEYGgDwAgANAAkKsCEYGgDwAgAAAA==.Deathmikee:BAABNQAECn9IAAMNAAoK7yJiEAA0AwANAAoKDSJiEAA0AwASAAoKnR1MDgC2AgAAAA==.Delilah:BAAANQAECgYIDQAAAA==.Delita:BAAANQAECgMIAwAAAA==.Demonea:BAAANQAECgEIAQAAAA==.Denari:BAAANQADCgcIBwABNQAECgoKSAABABEaAA==.Derek:BAAANQAECgUIBwABNQAECgkJGwAIAO0cAA==.',
Dr='Drakkenbreth:BAAANQAECgQIBAAAAA==.Drakos:BAAANQADCggIEAAAAA==.',
Du='Durton:BAABNQAECn9GAAMTAAoKVSLTAgDyAgATAAoKVSLTAgDyAgAUAAMKCgyQGAGrAAAAAA==.',
Ec='Echø:BAAANQADCgUIBQAAAA==.',
Ed='Edrency:BAAANQADCgYIBgAAAA==.',
Ef='Eferis:BAAANQAECggIDgAAAA==.',
El='Elderdorje:BAABNQAECn9SAAMGAAoKdh7LBQA7AwAGAAoKdh7LBQA7AwAHAAoK3wcpOwDPAAAAAA==.Elixe:BAAANQADCggICAAAAA==.Elmersglue:BAAANQAECgEIAQAAAA==.Elondre:BAABNQAECn9OAAIQAAoKsCOaBADUAwAQAAoKsCOaBADUAwAAAA==.',
En='Enjikoma:BAAANQADCgEIAQAAAA==.',
Ev='Evangeliné:BAAANQAECgYIEgABNQAECgoKRgAIAFAUAA==.',
Ex='Execfive:BAAANQADCgIIAQAAAA==.',
Fe='Femboi:BAABNQAECn9KAAILAAoKKCBYCgA1AwALAAoKKCBYCgA1AwAAAA==.',
Fi='Firecracker:BAAANQAECgYIDAAAAA==.',
Fo='Fortwooh:BAAANQADCgcIEwAAAA==.',
Fr='Freshlight:BAAANQAECgUICQABNQAFFAUIEQAGAKgSAA==.',
Fu='Fuurak:BAAANQAFFAEIAQAAAA==.',
Ga='Gado:BAAANQAECgUIBAABNQAFFAUIDQAKAJcLAA==.Galatea:BAACNQAFFH8KAAIVAAQK1RLDFwDQAAAVAAQK1RLDFwDQAAA1AAQKf1gAAhUACgq2I0AvAAwDABUACgq2I0AvAAwDAAAA.Galifen:BAABNQAECn9VAAIBAAoKfSbBAQDjAwABAAoKfSbBAQDjAwAAAA==.Gameplan:BAAANQADCgYICAAAAA==.Gank:BAABNQAECn8vAAIWAAoKoSKuBACLAwAWAAoKoSKuBACLAwAAAA==.Gardener:BAAANQABCgIIBAAAAA==.',
Gh='Ghreen:BAAANQAECgYICAAAAA==.',
Gi='Gilgahmesh:BAABNQAECn8oAAIRAAcK0A31NAA9AQARAAcK0A31NAA9AQAAAA==.',
Gn='Gnomegrown:BAABNQAECn8sAAIBAAkKTg9GLgCSAQABAAkKTg9GLgCSAQAAAA==.',
Go='Gothika:BAAANQADCgIIAgAAAA==.Goy:BAAANQAECgcIAQAAAA==.',
Gr='Grainbelt:BAAANQAECggIEgAAAA==.Gru:BAAANQAECgcIBwAAAA==.',
Gy='Gyrux:BAAANQAECgEIAQAAAA==.',
Ha='Halyer:BAAANQADCggIGwAAAA==.Hamalainen:BAABNQAECn8lAAMXAAoKiBKxBgDKAQAXAAkKHROxBgDKAQADAAkKuwqD0QBeAQABNQAFFAUIEQAGAKgSAA==.Harrydresden:BAAANQABCgIIBAAAAA==.Havøc:BAAANQAECgMIAwAAAA==.',
He='Helioboops:BAAANQADCggIEwAAAA==.',
Ho='Hobbz:BAACNQAFFH8MAAIVAAYK+hQDDgBrAQAVAAYK+hQDDgBrAQA1AAQKf0sAAhUACgpJJQ4LAEgDABUACgpJJQ4LAEgDAAAA.',
Il='Illandros:BAABNQAECn8uAAIJAAcKJBHVKgAvAQAJAAcKJBHVKgAvAQAAAA==.',
In='Inspire:BAACNQAFFH8SAAIYAAYKmhahBwCBAQAYAAYKmhahBwCBAQA1AAQKfywAAhgACgopI2cJAC8DABgACgopI2cJAC8DAAAA.',
Is='Isinia:BAAANQADCgEIAQAAAA==.Isira:BAAANQAECgcICQAAAA==.',
Ja='Jaína:BAAANQAECgIIAgABNQAECgUIDgAFAAAAAA==.',
Jc='Jcvd:BAAANQADCgYICwABNQAFFAUIEQAGAKgSAA==.',
Je='Jelina:BAABNQAECn8gAAMVAAcKrQh29AD8AAAVAAcKrQh29AD8AAARAAEKAACVgQAAAAAAAA==.',
Ji='Jiren:BAACNQAFFH8RAAIGAAUKqBLpBABiAQAGAAUKqBLpBABiAQA1AAQKf0AAAwYACgpMIMAJAO4CAAYACgpMIMAJAO4CAAcABAr2BltNAG8AAAAA.',
Jo='Johnson:BAABNQAECn8YAAIZAAkKDxSIEQAOAgAZAAkKDxSIEQAOAgAAAA==.Joran:BAABNQAECn8XAAIVAAYKqQnA+QArAQAVAAYKqQnA+QArAQAAAA==.',
La='Laststop:BAAANQADCgYIBQAAAA==.',
Le='Leanea:BAAANQAECgIIAgAAAA==.',
Li='Liera:BAABNQAECn8lAAINAAoKoQ8qLQB/AQANAAoKoQ8qLQB/AQAAAA==.Lightsac:BAAANQADCgYIBwAAAA==.Limmywinks:BAAANQAECgIIAgAAAA==.',
Ll='Lloydlei:BAAANQAECgcIDwAAAA==.',
Lu='Luminå:BAABNQAECn8sAAIPAAoKOR1tBADkAgAPAAoKOR1tBADkAgAAAA==.',
['Lå']='Låte:BAAANQADCgcIDwAAAA==.',
Ma='Maibisan:BAABNQAECn9nAAMOAAoKaSY4AQDsAwAOAAoKaSY4AQDsAwALAAgKBSJCHgBfAgAAAA==.Malificent:BAAANQAECgMIAwAAAA==.',
Mc='Mchack:BAAANQAECggIDwAAAA==.',
Me='Metaevoker:BAABNQAECn9TAAIaAAoK8xxkBQBrAgAaAAoK8xxkBQBrAgAAAA==.',
Mo='Monawah:BAABNQAECn8iAAIDAAgKJwv5jADwAQADAAgKJwv5jADwAQAAAA==.Mookong:BAAANQADCgYIBwABNQAECgQIBAAFAAAAAA==.Moonsliver:BAAANQAECgMIBwAAAA==.Moorf:BAABNQAECn8oAAMQAAoKMRG4QgAIAgAQAAkKERO4QgAIAgACAAUKBARhxwB9AAAAAA==.Morff:BAABNQAECn8bAAMaAAcKEwv/HwBWAQAaAAcKEwv/HwBWAQAbAAEK+gjXPgAlAAAAAA==.Morfie:BAAANQADCgUIBQABNQAECgcIGwAaABMLAA==.Motleychew:BAAANQADCggIFQAAAA==.',
My='Mystwolf:BAAANQAECgYICAAAAA==.',
Ne='Ned:BAAANQADCgMIAwABNQAECgUIDgAFAAAAAA==.',
Ni='Nightember:BAAANQAECgEIAQABNQAECgoKUgAGAHYeAA==.Nightski:BAABNQAECn8tAAIYAAoKtxaIFQB3AgAYAAoKtxaIFQB3AgAAAA==.Nizzari:BAAANQAECgMIBgABNQAFFAUIDQAKAJcLAA==.',
No='Nobuseri:BAABNQAECn8nAAIcAAoKSAz0TQDKAQAcAAoKSAz0TQDKAQAAAA==.Nothalyer:BAABNQAECn9CAAMbAAoKuQfvGgBJAQAbAAoKuQfvGgBJAQAKAAgKMQZ+DwDqAAAAAA==.',
['Nå']='Nåtrii:BAAANQAECgIIAwABNQAECggIGgAbAJ4IAA==.',
Ob='Obliviora:BAAANQADCgYIBgAAAA==.',
Og='Ogdi:BAAANQAECgUIDgAAAA==.',
Ol='Olaria:BAAANQADCgMIAwAAAA==.',
Oo='Ookook:BAAANQAECggIBwABNQAECgoKKgASAAgWAA==.',
Or='Orwasitgarp:BAAANQADCgYIBgABNQAECgUIDgAFAAAAAA==.Orwasitme:BAAANQAECgUIDgAAAA==.Orwasitmii:BAAANQADCgMJAwABNQAECgUIDgAFAAAAAA==.',
Pa='Paladinii:BAAANQAECgUIBQAAAA==.',
Ph='Philonk:BAABNQAECn8rAAMHAAoKTxFOHQC5AQAHAAoKTxFOHQC5AQAdAAEK/gXkKgAlAAAAAA==.',
Pj='Pjxyo:BAABNQAECn8cAAMMAAkKlxqzPACsAAADAAkK6RjLswBKAQAMAAQKmA2zPACsAAAAAA==.',
Po='Polytots:BAACNQAFFH8SAAMQAAcKZg/RDgBiAQAQAAcKZg/RDgBiAQACAAIKcwkNJwCQAAA1AAQKf1gAAxAACgreJP4BAMgDABAACgreJP4BAMgDAAIAAwrrEmvMAHQAAAAA.',
Ps='Psycototem:BAAANQAECgMIBwAAAA==.',
Ra='Ragñar:BAAANQAECgUIBQAAAA==.Razering:BAAANQAECgEIAQAAAA==.Razius:BAAANQAECggIDgAAAA==.',
Re='Rebexha:BAABNQAECn8ZAAMPAAYKUwreQgC5AAAPAAQKCwjeQgC5AAAeAAYKeQcM0ACxAAAAAA==.Replayjade:BAAANQADCgEIAQAAAA==.',
Ri='Ricklepick:BAAANQAECggIEQABNQAFFAUIEQAGAKgSAA==.',
Ro='Romaeus:BAAANQADCgYIBwAAAA==.',
Ru='Ruskie:BAAANQADCgEIAQAAAA==.',
Ry='Ryzenther:BAAANQAECgIJAwAAAA==.',
['Rà']='Ràgnar:BAAANQAECgMIAgAAAA==.Ràgñar:BAAANQADCgYIEQAAAA==.',
Sa='Sanctis:BAAANQADCgYIBgAAAA==.',
Sc='Scarpa:BAAANQAECgEIAQABNQAECgoKSAABABEaAA==.Scathclipe:BAABNQAECn8vAAMWAAkKUxeELgAqAgAWAAkKRxSELgAqAgAfAAkK+xT/CAAEAgAAAA==.',
Se='Sealedfate:BAAANQAECgEIBAAAAA==.Seancodi:BAAANQAECgEIAQABNQAFFAcIFwALAEEZAA==.Senomage:BAABNQAECn8nAAMgAAoKcyJbNgAcAwAgAAoKcyJbNgAcAwAhAAMK/R35HwDqAAAAAA==.Serphentos:BAAANQABCgIIAgAAAA==.',
Sh='Shasato:BAACNQAFFH8GAAIiAAIKNhL2BgB/AAAiAAIKNhL2BgB/AAA1AAQKfz4AAyIACgqRIScGAPICACIACgqRIScGAPICAAEABgoKEQtCAB8BAAAA.Shockss:BAAANQAECgYICwAAAA==.',
Si='Sidie:BAAANQADCgMIAwAAAA==.Sindora:BAAANQADCgEIAQAAAA==.Sizouze:BAABNQAECn9FAAIIAAoK3w9JWwDRAQAIAAoK3w9JWwDRAQAAAA==.',
Sk='Skeeter:BAAANQADCgYIBgABNQAECgoKKwAPAO8XAA==.Skyepic:BAACNQAFFH8kAAMEAAkKBBqXAgCAAgAEAAkKBBqXAgCAAgARAAEKTgWlEQA+AAA1AAQKfycAAgQACgpyJRQBAOMDAAQACgpyJRQBAOMDAAAA.Skylight:BAAANQAECggIDAAAAA==.',
Sn='Sneakfu:BAABNQAECn86AAMWAAkKnBZbMwAPAgAWAAgKjxBbMwAPAgAcAAkKqxUGTQDNAQAAAA==.Snugwalnut:BAACNQAFFH8TAAIQAAgK4hDgCADDAQAQAAgK4hDgCADDAQA1AAQKfzMAAhAACgpoIYg0AI0CABAACgpoIYg0AI0CAAAA.',
So='Soejoedi:BAABNQAECn9IAAIBAAoKERo8GABOAgABAAoKERo8GABOAgAAAA==.Sorrowin:BAAANQABCgIIAgAAAA==.',
Sp='Spicyburrito:BAAANQAECgIIAgAAAA==.',
St='Stitchzpls:BAAANQAECgIIBAAAAA==.',
Su='Sunraku:BAAANQAECgMIAwAAAA==.',
Ta='Taintedrush:BAACNQAFFH8QAAIjAAYKQxeUAQBOAQAjAAYKQxeUAQBOAQA1AAQKfzoAAiMACgoXHRwDANMCACMACgoXHRwDANMCAAAA.Takuan:BAAANQAECgIIAgAAAA==.Tarhostamir:BAAANQAFFAEIAQAAAA==.Taurup:BAAANQADCgYIEwABNQAFFAUIDQAKAJcLAA==.Tazz:BAABNQAECn8kAAMDAAoKKwUHuABCAQADAAoKKwUHuABCAQAMAAEKAABwoAAaAAAAAA==.',
Te='Teenjus:BAAANQADCggIFgAAAA==.',
Th='Thaluus:BAAANQADCgUIDQAAAA==.Thanossnap:BAAANQABCgQIBgABNQAECgoKUgAGAHYeAA==.Thaysinga:BAABNQAECn82AAINAAkKaRUlGwAMAgANAAkKaRUlGwAMAgAAAA==.Thelandlord:BAAANQAECgIIAgAAAA==.Thunderblast:BAABNQAECn8ZAAIUAAYKxhi3tACZAQAUAAYKxhi3tACZAQAAAA==.Thuss:BAAANQADCgQIBAAAAA==.',
To='Totemtosser:BAAANQAECgEIAQAAAA==.',
Ut='Utzon:BAAANQAECgIIAgABNQAECgoKSAABABEaAA==.',
Va='Vaedan:BAAANQADCgcIEwAAAA==.Valkyrrie:BAAANQADCggIEAABNQADCggIGwAFAAAAAA==.Vander:BAABNQAECn8ZAAMIAAYKkh9UXADOAQAIAAYKkh9UXADOAQAJAAEKAABnjwAbAAAAAA==.Vannder:BAAANQAECgEIAgABNQAECgYIGQAIAJIfAA==.Vayper:BAABNQAECn9XAAQJAAoKNiLDBgBsAwAJAAoKNiLDBgBsAwAIAAIK4gop4wB/AAAkAAEK8gRELwAmAAAAAA==.Vaypshawk:BAAANQADCggIFAABNQAECgoKVwAJADYiAA==.',
Ve='Veins:BAAANQAECgYIBgAAAA==.',
Vi='Viigo:BAAANQABCgQIBAAAAA==.',
['Vë']='Vënöm:BAAANQAECgcICAABNQAECgoKLAAPADkdAA==.',
Wa='Waggo:BAABNQAECn8hAAICAAcKrBAWgwCdAQACAAcKrBAWgwCdAQAAAA==.Waken:BAAANQAECgcICQAAAA==.Warm:BAAANQAFFAEIAQAAAA==.Waterboy:BAAANQADCgcIDAABNQADCgUIBgAFAAAAAA==.',
We='Weemsy:BAAANQADCgYIBgAAAA==.Wellmet:BAAANQAECgEIAQAAAA==.',
Wi='Wildfire:BAACNQAFFH8KAAIXAAcKDRxFAAA9AgAXAAcKDRxFAAA9AgA1AAQKf04AAhcACgrSJhoAAJgDABcACgrSJhoAAJgDAAAA.',
Wo='Wolfhammer:BAABNQAECn9FAAIZAAoKex1WCABgAgAZAAoKex1WCABgAgAAAA==.',
Wr='Wreckadin:BAABNQAECn8oAAIVAAoK5B3VMQCbAgAVAAoK5B3VMQCbAgAAAA==.',
Ya='Yaztraz:BAABNQAECn86AAQQAAoKmBwUPwBkAgAQAAoKmBwUPwBkAgACAAcKig0ojAD0AAAlAAEKFQfDOAAwAAAAAA==.',
Ye='Yellowflag:BAAANQAECggIEQABNQAFFAkJMAASAHEgAA==.',
Za='Zarturion:BAAANQAECgEIAQAAAA==.',
Zo='Zod:BAACNQAFFH8NAAMKAAUKlwuyCQC3AAAKAAUKlwuyCQC3AAAaAAEKQQJCEQAyAAA1AAQKf0oAAwoACgoJGcYEALACAAoACgoJGcYEALACABoABgpqDs4UAOkAAAAA.',
['Às']='Àsh:BAABNQAECn8nAAIIAAoKpRGGXwACAgAIAAoKpRGGXwACAgAAAA==.',
['Év']='Évangeline:BAAANQAECgcIEgABNQAECgoKRgAIAFAUAA==.',
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

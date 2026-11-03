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

local lookup = {'Druid-Balance','Shaman-Elemental','Paladin-Holy','Unknown-Unknown','Monk-Mistweaver','Monk-Windwalker','Priest-Holy','Priest-Shadow','Evoker-Augmentation','DemonHunter-Devourer','Hunter-Marksmanship','Hunter-BeastMastery','DeathKnight-Unholy','DemonHunter-Havoc','Warlock-Destruction','Paladin-Protection','DeathKnight-Blood','Warrior-Fury','Warrior-Arms','Shaman-Restoration','Paladin-Retribution','Rogue-Assassination','Hunter-Survival','Druid-Restoration','Warrior-Protection','Evoker-Devastation','Evoker-Preservation','Rogue-Subtlety','Warlock-Demonology','Rogue-Outlaw','Mage-Arcane','Mage-Frost','Druid-Guardian','Warlock-Affliction','Priest-Discipline',}
local provider = {region='US',realm='Executus',name='US',type='weekly',zone=53,date='2026-11-03',data={Al='Alodiar:BAAANQADCgUICQAAAA==.',
An='Andersen:BAAANQADCgEIAgAAAA==.Andryu:BAABNQAECn8/AAIBAAoKRhRZGgACAgABAAoKRhRZGgACAgAAAA==.Annde:BAABNQAECn8zAAICAAoKIxiSOQCQAgACAAoKIxiSOQCQAgAAAA==.Anyana:BAAANQADCgQIBQABNQAECgcIGwADAKocAA==.',
Ar='Ardre:BAAANQADCgUIBQABNQADCgUICQAEAAAAAA==.Arkanis:BAAANQADCgEIAQAAAA==.Artemus:BAACNQAFFH8MAAMFAAcKfwtSBgAsAQAFAAUK1gNSBgAsAQAGAAUKlwMPDACDAAA1AAQKfzYAAwUACgpcH+oJAOoCAAUACgpcH+oJAOoCAAYABwqODoQ0AHEBAAE1AAQKBggJAAQAAAAA.Arïel:BAABNQAECn8ZAAMHAAkKSxDdpwAeAQAHAAYKDRXdpwAeAQAIAAcK2guuKQD8AAAAAA==.',
Be='Beeftoteeth:BAAANQAECgYIBwAAAA==.Ber:BAABNQAECn8xAAIHAAoKYBzaEAAqAwAHAAoKYBzaEAAqAwABNQAFFAUIDQAJAJcLAA==.Bexxy:BAAANQAECgYIDgAAAA==.',
Bi='Bibicrits:BAAANQABCggIDgABNQAECgoKQgAKAGQeAA==.',
Bl='Blueseno:BAAANQADCgYIBgAAAA==.',
Bo='Bouras:BAAANQAECgYIEQAAAA==.',
Br='Broadfang:BAACNQAFFH8gAAMLAAcKDhrzBwDLAQALAAYKrhTzBwDLAQAMAAYK+RqiCgAXAQA1AAQKf0QAAwsACgqSIp4UALoCAAsACQrnIZ4UALoCAAwABgr5IitPAPABAAAA.',
Bu='Bubbleoseven:BAAANQAECgYICAAAAA==.Bullorly:BAACNQAFFH8KAAINAAUK3B3YBADeAQANAAUK3B3YBADeAQA1AAQKfzkAAg0ACgqoJXUFAKEDAA0ACgqoJXUFAKEDAAAA.',
Ca='Catirus:BAAANQADCgYICQAAAA==.',
Ch='Chareddh:BAAANQADCgMIAwABNQAECgoKSAAFAHYeAA==.Cheehoo:BAAANQADCggIBwAAAA==.Chunt:BAAANQADCgcICAAAAA==.',
Cl='Cleo:BAABNQAECn8WAAMOAAcKWAEkfQCCAAAOAAcKWAEkfQCCAAAKAAUK7QAiYwBeAAAAAA==.Clipe:BAABNQAECn8gAAIPAAoKLxtDAQCbAgAPAAoKLxtDAQCbAgAAAA==.Clipee:BAAANQADCgEIAQAAAA==.Clipeskeg:BAAANQADCgEIAQAAAA==.Clipex:BAAANQADCgMIAwAAAA==.Clipey:BAAANQADCggIDgAAAA==.',
Co='Coldsnap:BAAANQADCgQIBgAAAA==.Connor:BAAANQADCgYICgAAAA==.Control:BAAANQAECgMIAwAAAA==.',
Cr='Crimsonpaw:BAAANQAECgcIBwAAAA==.Crispicrits:BAAANQAECggIEQABNQAFFAQIBgAHALgVAA==.',
Cy='Cynîc:BAAANQAECgMIBgAAAA==.',
Da='Dalaran:BAABNQAECn9JAAIKAAoKJg3oGQCqAQAKAAoKJg3oGQCqAQAAAA==.Darenas:BAACNQAFFH8NAAIIAAcKPQ75CQBeAQAIAAcKPQ75CQBeAQA1AAQKfzsAAggACgpgHV4OAAkDAAgACgpgHV4OAAkDAAAA.Darkwing:BAAANQADCgEIAgABNQAECgcIHwAQANANAA==.',
De='Deathbooze:BAABNQAECn8nAAINAAkKsCEYGgDwAgANAAkKsCEYGgDwAgAAAA==.Deathmikee:BAABNQAECn8+AAMNAAoKPCJiEAA0AwANAAoKDSJiEAA0AwARAAoKgxp/EAB6AgAAAA==.Delilah:BAAANQAECgYIDQAAAA==.Delita:BAAANQAECgMIAwAAAA==.Demonea:BAAANQAECgEIAQAAAA==.Denari:BAAANQADCgcIBwABNQAECgoKPgABAOkVAA==.Derek:BAAANQAECgUIBwABNQAECgcIGQAHAJ8bAA==.',
Dr='Drakkenbreth:BAAANQAECgQIBAAAAA==.Drakos:BAAANQADCggIEAAAAA==.',
Du='Durton:BAABNQAECn9CAAMSAAoKtCE5AgDuAgASAAoKtCE5AgDuAgATAAMKCgyQGAGrAAAAAA==.',
Ec='Echø:BAAANQADCgUIBQAAAA==.',
Ed='Edrency:BAAANQADCgYIBgAAAA==.',
Ef='Eferis:BAAANQAECggIDQAAAA==.',
El='Elderdorje:BAABNQAECn9IAAMFAAoKdh5nBABJAwAFAAoKdh5nBABJAwAGAAcKUAVDRwDlAAAAAA==.Elmersglue:BAAANQAECgEIAQAAAA==.Elondre:BAABNQAECn9NAAIUAAoKsCP/AgDoAwAUAAoKsCP/AgDoAwAAAA==.',
En='Enjikoma:BAAANQABCggIDgAAAA==.',
Ev='Evangeliné:BAAANQAECgYICgABNQAECgcIDAAEAAAAAA==.',
Ex='Execfive:BAAANQADCgIIAQAAAA==.',
Fe='Femboi:BAABNQAECn9CAAIKAAoKZB5YCgA1AwAKAAoKZB5YCgA1AwAAAA==.',
Fi='Firecracker:BAAANQAECgYIDAAAAA==.',
Fo='Fortwooh:BAAANQADCgcIFgAAAA==.',
Fr='Freshlight:BAAANQAECgUICQABNQAFFAUIDQAFAOsRAA==.',
Fu='Fuurak:BAAANQAFFAEIAQAAAA==.',
Ga='Gado:BAAANQAECgUIBAABNQAFFAUIDQAJAJcLAA==.Galatea:BAACNQAFFH8KAAIVAAQK1RKQEQDWAAAVAAQK1RKQEQDWAAA1AAQKf1QAAhUACgqnIkAvAAwDABUACgqnIkAvAAwDAAAA.Galifen:BAABNQAECn9LAAIBAAoKfSbBAQDjAwABAAoKfSbBAQDjAwAAAA==.Gameplan:BAAANQADCgYICAAAAA==.Gank:BAABNQAECn8vAAIWAAoKoSKuBACLAwAWAAoKoSKuBACLAwAAAA==.Gardener:BAAANQADCgEIAQAAAA==.',
Gh='Ghreen:BAAANQAECgYICAAAAA==.',
Gi='Gigathreat:BAAANQADCgEIAQAAAA==.Gilgahmesh:BAABNQAECn8fAAIQAAcK0A31NAA9AQAQAAcK0A31NAA9AQAAAA==.',
Gn='Gnomegrown:BAABNQAECn8fAAIBAAcKqguRQADzAAABAAcKqguRQADzAAAAAA==.',
Go='Gothika:BAAANQADCgIIAgAAAA==.Goy:BAAANQAECgcIAQAAAA==.',
Gr='Grainbelt:BAAANQAECggIDQAAAA==.Gru:BAAANQAECgcIBwAAAA==.',
Gy='Gyrux:BAAANQAECgEIAQAAAA==.',
Ha='Halyer:BAAANQADCggIHAAAAA==.Hamalainen:BAABNQAECn8kAAMXAAoKYhFqBgCUAQAXAAgKghNqBgCUAQAMAAkKuwqD0QBeAQABNQAFFAUIDQAFAOsRAA==.Harrydresden:BAAANQADCgEIAQAAAA==.Havøc:BAAANQAECgMIAwAAAA==.',
He='Helioboops:BAAANQADCggIEgAAAA==.',
Ho='Hobbz:BAACNQAFFH8MAAIVAAYK+hQDDgBrAQAVAAYK+hQDDgBrAQA1AAQKf0IAAhUACgoyJSQJAEQDABUACgoyJSQJAEQDAAAA.',
Il='Illandros:BAABNQAECn8lAAIIAAcKyBBoJAAkAQAIAAcKyBBoJAAkAQAAAA==.',
In='Inspire:BAACNQAFFH8PAAIYAAYKyBKhBwCBAQAYAAYKyBKhBwCBAQA1AAQKfywAAhgACgopI2cJAC8DABgACgopI2cJAC8DAAAA.',
Is='Isinia:BAAANQADCgEIAQAAAA==.Isira:BAAANQAECgcICQAAAA==.',
Ja='Jaína:BAAANQAECgIIAgABNQAECgYIDgAEAAAAAA==.',
Jc='Jcvd:BAAANQADCgYICwABNQAFFAUIDQAFAOsRAA==.',
Je='Jelina:BAABNQAECn8UAAMVAAYKkwZaAQGuAAAVAAYKkwZaAQGuAAAQAAEKAAB2cQAAAAAAAA==.',
Ji='Jiren:BAACNQAFFH8NAAIFAAUK6xGHAwBoAQAFAAUK6xGHAwBoAQA1AAQKfzsAAwUACgpMIMAJAO4CAAUACgpMIMAJAO4CAAYAAwokBjZMAEoAAAAA.',
Jo='Johnson:BAABNQAECn8YAAIZAAkKDxSIEQAOAgAZAAkKDxSIEQAOAgAAAA==.Joran:BAABNQAECn8XAAIVAAYKqQnA+QArAQAVAAYKqQnA+QArAQAAAA==.',
La='Laststop:BAAANQADCgYIBQAAAA==.',
Le='Leanea:BAAANQAECgIIAgAAAA==.',
Li='Liera:BAABNQAECn8iAAINAAgKdxGPLwA+AQANAAgKdxGPLwA+AQAAAA==.Lightsac:BAAANQADCgYIBwAAAA==.Limmywinks:BAAANQAECgIIAgAAAA==.',
Ll='Lloydlei:BAAANQAECgcIDwAAAA==.',
Lu='Luminå:BAABNQAECn8sAAIPAAoKOR1tBADkAgAPAAoKOR1tBADkAgAAAA==.',
['Lå']='Låte:BAAANQADCgcIBwAAAA==.',
Ma='Maibisan:BAABNQAECn9mAAMOAAoKaSb5AAB8AwAOAAoKaSb5AAB8AwAKAAgKBSJCHgBfAgAAAA==.Malificent:BAAANQAECgMIAwAAAA==.',
Mc='Mchack:BAAANQADCgYIBAAAAA==.',
Me='Metaevoker:BAABNQAECn9PAAIaAAoKphvSBABVAgAaAAoKphvSBABVAgAAAA==.',
Mo='Monawah:BAABNQAECn8iAAIMAAgKJwv5jADwAQAMAAgKJwv5jADwAQAAAA==.Mookong:BAAANQADCgYIBwABNQAECgQIBAAEAAAAAA==.Moonsliver:BAAANQAECgQIBwAAAA==.Moorf:BAABNQAECn8jAAMUAAoKvw8IOwD6AQAUAAkKdhEIOwD6AQACAAUKBAQSrAB9AAAAAA==.Morff:BAABNQAECn8bAAMaAAcKEwv/HwBWAQAaAAcKEwv/HwBWAQAbAAEK+gjpNwAlAAAAAA==.Motleychew:BAAANQADCggIFQAAAA==.',
My='Mystwolf:BAAANQAECgUJBwAAAA==.',
Ne='Ned:BAAANQADCgMIAwABNQAECgYIDgAEAAAAAA==.',
Ni='Nightember:BAAANQAECgEIAQABNQAECgoKSAAFAHYeAA==.Nightski:BAABNQAECn8iAAIYAAgK0xfuFwAIAgAYAAgK0xfuFwAIAgAAAA==.Nizzari:BAAANQAECgMIBgABNQAFFAUIDQAJAJcLAA==.',
No='Nobuseri:BAABNQAECn8VAAIcAAkKnworTgB7AQAcAAkKnworTgB7AQAAAA==.Nothalyer:BAABNQAECn9CAAMbAAoKuQdCFgBPAQAbAAoKuQdCFgBPAQAJAAgKMQbjDADrAAAAAA==.',
['Nå']='Nåtrii:BAAANQAECgEIAQABNQAECggIGgAbAJ4IAA==.',
Ob='Obliviora:BAAANQADCgYIBgAAAA==.',
Og='Ogdi:BAAANQAECgYIDgAAAA==.',
Ol='Olaria:BAAANQADCgMIAwAAAA==.',
Oo='Ookook:BAAANQAECggIBwABNQAECgoKGAARACQOAA==.',
Or='Orwasitgarp:BAAANQADCgYIBgABNQAECgYIDgAEAAAAAA==.Orwasitme:BAAANQAECgYIDgAAAA==.Orwasitmii:BAAANQADCgMJBQABNQAECgYIDgAEAAAAAA==.',
Pa='Paladinii:BAAANQAECgUIBQAAAA==.',
Ph='Philonk:BAABNQAECn8jAAIGAAoKbRC6JgDtAQAGAAoKbRC6JgDtAQAAAA==.',
Pj='Pjxyo:BAABNQAECn8bAAMMAAgKlxpOkABNAQAMAAgK6RhOkABNAQALAAQKmA2yMgCwAAAAAA==.',
Po='Polytots:BAACNQAFFH8SAAMUAAcKZg/RDgBiAQAUAAcKZg/RDgBiAQACAAIKcwkNJwCQAAA1AAQKf1AAAxQACgreJP4BAMgDABQACgreJP4BAMgDAAIAAwrrEh+xAHQAAAAA.',
Ps='Psycototem:BAAANQAECgMIBwAAAA==.',
Ra='Ragñar:BAAANQAECgUIBQAAAA==.Razering:BAAANQAECgEIAQAAAA==.Razius:BAAANQAECggIDgAAAA==.',
Re='Rebexha:BAABNQAECn8ZAAMPAAYKUwreQgC5AAAPAAQKCwjeQgC5AAAdAAYKeQcwtgCzAAAAAA==.Replayjade:BAAANQADCgEIAQAAAA==.',
Rh='Rheia:BAAANQADCgEIAQAAAA==.',
Ri='Ricklepick:BAAANQAECggIEQABNQAFFAUIDQAFAOsRAA==.',
Ro='Romaeus:BAAANQADCgYIBwAAAA==.',
Ru='Ruskie:BAAANQADCgEIAQAAAA==.',
Ry='Ryzenther:BAAANQAECgIJAwAAAA==.',
['Rà']='Ràgnar:BAAANQAECgMIAgAAAA==.Ràgñar:BAAANQADCgYIEgAAAA==.',
Sa='Sanctis:BAAANQADCgYIBgAAAA==.',
Sc='Scarpa:BAAANQAECgEIAQABNQAECgoKPgABAOkVAA==.Scathclipe:BAABNQAECn8nAAMWAAkKQxaELgAqAgAWAAkKrxKELgAqAgAeAAgKvxT/CAAEAgAAAA==.',
Se='Sealedfate:BAAANQAECgEIAwAAAA==.Seancodi:BAAANQAECgEIAQABNQAFFAcIFwAKAEEZAA==.Senomage:BAABNQAECn8nAAMfAAoKcyJbNgAcAwAfAAoKcyJbNgAcAwAgAAMK/R35HwDqAAAAAA==.Serphentos:BAAANQADCgEIAQAAAA==.',
Sh='Shasato:BAABNQAECn81AAMhAAoKrCAHBgAzAwAhAAoKrCAHBgAzAwABAAQKVAzfWQCPAAAAAA==.Shazrast:BAAANQADCgQIBAAAAA==.Shockss:BAAANQAECgYICwAAAA==.',
Si='Sidie:BAAANQADCgMIAwAAAA==.Sindora:BAAANQADCgEIAQAAAA==.Sizouze:BAABNQAECn87AAIHAAoKvw/cTQDIAQAHAAoKvw/cTQDIAQAAAA==.',
Sk='Skeeter:BAAANQADCgYIBgABNQAECgoKKwAPAO8XAA==.Skyepic:BAACNQAFFH8jAAMDAAgKixqXAgCAAgADAAgKixqXAgCAAgAQAAEKTgWlEQA+AAA1AAQKfycAAgMACgpyJRQBAOMDAAMACgpyJRQBAOMDAAAA.Skylight:BAAANQAECggIDAAAAA==.',
Sn='Sneakfu:BAABNQAECn86AAMWAAkKnBZbMwAPAgAWAAgKjxBbMwAPAgAcAAkKqxV3PADGAQAAAA==.Snugwalnut:BAACNQAFFH8RAAIUAAcKtg7gCADDAQAUAAcKtg7gCADDAQA1AAQKfzMAAhQACgpoIYg0AI0CABQACgpoIYg0AI0CAAAA.',
So='Soejoedi:BAABNQAECn8+AAIBAAoK6RWrJwCYAgABAAoK6RWrJwCYAgAAAA==.Sorrowin:BAAANQADCgEIAQAAAA==.',
Sp='Spicyburrito:BAAANQAECgIIAgAAAA==.',
St='Stitchzpls:BAAANQAECgIIBAAAAA==.',
Ta='Taintedrush:BAACNQAFFH8NAAIiAAUK8BG6AQDpAAAiAAUK8BG6AQDpAAA1AAQKfzkAAiIACgoXHRwDANMCACIACgoXHRwDANMCAAAA.Tarhostamir:BAAANQAFFAEIAQAAAA==.Taurup:BAAANQADCgYIEwABNQAFFAUIDQAJAJcLAA==.Tazz:BAABNQAECn8jAAMMAAkKlwQysQALAQAMAAkKlwQysQALAQALAAEKAABwoAAaAAAAAA==.',
Te='Teenjus:BAAANQADCggIFQAAAA==.',
Th='Thaluus:BAAANQADCgUICQAAAA==.Thanossnap:BAAANQADCgEIAQABNQAECgoKSAAFAHYeAA==.Thaysinga:BAABNQAECn82AAINAAkKaRUPFgARAgANAAkKaRUPFgARAgAAAA==.Thelandlord:BAAANQAECgIIAgAAAA==.Thunderblast:BAABNQAECn8YAAITAAYKxhi3tACZAQATAAYKxhi3tACZAQAAAA==.Thuss:BAAANQADCgQIBAAAAA==.',
To='Totemtosser:BAAANQAECgEIAQAAAA==.',
Tr='Trollor:BAAANQADCggIHgAAAA==.',
Ut='Utzon:BAAANQAECgIIAgABNQAECgoKPgABAOkVAA==.',
Va='Vaedan:BAAANQADCgcIEwAAAA==.Valkyrrie:BAAANQADCgcICgABNQADCggIHAAEAAAAAA==.Vander:BAABNQAECn8ZAAMHAAYKkh8DSADfAQAHAAYKkh8DSADfAQAIAAEKAABnjwAbAAAAAA==.Vannder:BAAANQAECgEIAgABNQAECgYIGQAHAJIfAA==.Vayper:BAABNQAECn9NAAQIAAoKNiLDBgBsAwAIAAoKNiLDBgBsAwAHAAIK4gop4wB/AAAjAAEK8gRELwAmAAAAAA==.Vaypshawk:BAAANQADCggIFAABNQAECgoKTQAIADYiAA==.',
Ve='Veins:BAAANQAECgMIAgAAAA==.',
Vi='Viigo:BAAANQABCgQIBAAAAA==.',
['Vë']='Vënöm:BAAANQAECgcICAABNQAECgoKLAAPADkdAA==.',
Wa='Waggo:BAABNQAECn8hAAICAAcKrBAWgwCdAQACAAcKrBAWgwCdAQAAAA==.Waken:BAAANQAECgcICQAAAA==.Warm:BAAANQAFFAEIAQAAAA==.Waterboy:BAAANQADCgcIDAABNQADCgUIBgAEAAAAAA==.',
We='Weemsy:BAAANQADCgYIBgAAAA==.Wellmet:BAAANQAECgEIAQAAAA==.',
Wi='Wildfire:BAACNQAFFH8KAAIXAAcKDRxFAAA9AgAXAAcKDRxFAAA9AgA1AAQKf0QAAhcACgrSJhAAAJ0DABcACgrSJhAAAJ0DAAAA.',
Wo='Wolfhammer:BAABNQAECn9EAAIZAAoKZx0iBgBtAgAZAAoKZx0iBgBtAgAAAA==.',
Wr='Wreckadin:BAABNQAECn8kAAIVAAoKUh0rNABmAgAVAAoKUh0rNABmAgAAAA==.',
Ya='Yaztraz:BAABNQAECn85AAMUAAoKmBwUPwBkAgAUAAoKmBwUPwBkAgACAAcKig1fdAD0AAAAAA==.',
Ye='Yellowflag:BAAANQAECggIEQABNQAFFAkJKAARAHEgAA==.',
Za='Zaether:BAAANQADCgEIAQAAAA==.Zandari:BAAANQADCgEIAgAAAA==.Zarturion:BAAANQAECgEIAQAAAA==.',
Zo='Zod:BAACNQAFFH8NAAMJAAUKlwvlBgDDAAAJAAUKlwvlBgDDAAAaAAEKQQJCEQAyAAA1AAQKf0UAAwkACgp9GMYEALACAAkACgp9GMYEALACABoABgpqDjcSAOQAAAAA.',
['Às']='Àsh:BAABNQAECn8dAAIHAAoKfhGGXwACAgAHAAoKfhGGXwACAgAAAA==.',
['Év']='Évangeline:BAAANQAECgcIDAAAAA==.',
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

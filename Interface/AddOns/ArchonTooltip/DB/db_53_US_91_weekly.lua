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

local lookup = {'Druid-Balance','Shaman-Elemental','Paladin-Holy','Unknown-Unknown','Monk-Mistweaver','Monk-Windwalker','Priest-Holy','Priest-Shadow','Evoker-Augmentation','DemonHunter-Devourer','Hunter-BeastMastery','Hunter-Marksmanship','DeathKnight-Unholy','DemonHunter-Havoc','Warlock-Destruction','Shaman-Restoration','Paladin-Protection','DeathKnight-Blood','Warrior-Fury','Warrior-Arms','Paladin-Retribution','Rogue-Assassination','Hunter-Survival','Druid-Restoration','Warrior-Protection','Evoker-Devastation','Evoker-Preservation','Rogue-Subtlety','Warlock-Demonology','Druid-Feral','Rogue-Outlaw','Mage-Arcane','Mage-Frost','Druid-Guardian','Warlock-Affliction','Priest-Discipline','Shaman-Enhancement',}
local provider = {region='US',realm='Executus',name='US',type='weekly',zone=53,date='2026-11-10',data={Al='Alodiar:BAAANQADCgUICQAAAA==.',
An='Andersen:BAAANQADCgEIAQAAAA==.Andryu:BAABNQAECn9FAAIBAAoKRhTXHQD/AQABAAoKRhTXHQD/AQAAAA==.Annde:BAABNQAECn8zAAICAAoKIxiSOQCQAgACAAoKIxiSOQCQAgAAAA==.Anyana:BAAANQADCgQIBAABNQAECgcIGwADAKocAA==.',
Ar='Ardre:BAAANQADCgUIBQABNQADCgUICQAEAAAAAA==.Artemus:BAACNQAFFH8MAAMFAAcKfwtSBgAsAQAFAAUK1gNSBgAsAQAGAAUKlwPhDgCcAAA1AAQKfzYAAwUACgpcH+oJAOoCAAUACgpcH+oJAOoCAAYABwqODoQ0AHEBAAE1AAQKBggJAAQAAAAA.Arïel:BAABNQAECn8aAAMHAAoKZBHdpwAeAQAHAAcK8BXdpwAeAQAIAAcK2gvHLgD7AAAAAA==.',
Be='Beeftoteeth:BAAANQAECgYICgAAAA==.Ber:BAABNQAECn87AAIHAAoK7hzJEgAyAwAHAAoK7hzJEgAyAwABNQAFFAUIDQAJAJcLAA==.Bexxy:BAAANQAECgUIEAAAAA==.',
Bi='Bibicrits:BAAANQAECgEIAQABNQAECgoKSAAKAJ4eAA==.',
Bl='Blueseno:BAAANQADCgYIBgAAAA==.',
Bo='Bouras:BAAANQAECgYIEQAAAA==.',
Br='Broadfang:BAACNQAFFH8iAAMLAAgKXRYzCABTAQAMAAYKrhTzBwDLAQALAAcKXBYzCABTAQA1AAQKf0cAAwwACgqXIp4UALoCAAwACQrnIZ4UALoCAAsABgpXI/NZAP4BAAAA.',
Bu='Bubbleoseven:BAAANQAECgYICQAAAA==.Bullorly:BAACNQAFFH8KAAINAAUK3B3YBADeAQANAAUK3B3YBADeAQA1AAQKfzsAAg0ACgqoJXUFAKEDAA0ACgqoJXUFAKEDAAAA.',
Ca='Catirus:BAAANQADCgYICAAAAA==.',
Ch='Chareddh:BAAANQADCgMIAwABNQAECgoKTQAFAHYeAA==.Cheehoo:BAAANQADCggIBwAAAA==.Chunt:BAAANQADCgcIBwAAAA==.',
Cl='Cleo:BAABNQAECn8WAAMOAAcKWAEkfQCCAAAOAAcKWAEkfQCCAAAKAAUK7QAiYwBeAAAAAA==.Clipe:BAABNQAECn8kAAIPAAoKuhuAAQCcAgAPAAoKuhuAAQCcAgAAAA==.Clipee:BAAANQADCgEIAQAAAA==.Clipeskeg:BAAANQAECgEIAQAAAA==.Clipex:BAAANQADCgMIAwAAAA==.Clipey:BAAANQADCggIDgAAAA==.',
Co='Coldsnap:BAAANQADCgQIBgAAAA==.Connor:BAAANQADCgYICgAAAA==.Control:BAAANQAECgMIBQAAAA==.',
Cr='Crimsonpaw:BAAANQAECggICAAAAA==.Crispicrits:BAABNQAECn8aAAIQAAkKXBTbPQAIAgAQAAkKXBTbPQAIAgABNQAFFAQIBgAHALgVAA==.',
Cy='Cynîc:BAAANQAECgMIBgAAAA==.',
Da='Dalaran:BAABNQAECn9JAAIKAAoKJg2dHQCkAQAKAAoKJg2dHQCkAQAAAA==.Darenas:BAACNQAFFH8NAAIIAAcKPQ75CQBeAQAIAAcKPQ75CQBeAQA1AAQKfzwAAggACgpsHl4OAAkDAAgACgpsHl4OAAkDAAAA.Darkwing:BAAANQAECgEIAQABNQAECgcIJAARANANAA==.',
De='Deathbooze:BAABNQAECn8nAAINAAkKsCEYGgDwAgANAAkKsCEYGgDwAgAAAA==.Deathmikee:BAABNQAECn9DAAMNAAoK7yJiEAA0AwANAAoKDSJiEAA0AwASAAoKnR00DQC8AgAAAA==.Delilah:BAAANQAECgYIDwAAAA==.Delita:BAAANQAECgMIAwAAAA==.Demonea:BAAANQAECgEIAQAAAA==.Denari:BAAANQADCgcIBwABNQAECgoKSAABABEaAA==.Derek:BAAANQAECgUICAABNQAECgcIGQAHAJ8bAA==.',
Dr='Drakkenbreth:BAAANQAECgQIBAAAAA==.Drakos:BAAANQADCggIEAAAAA==.',
Du='Durton:BAABNQAECn9GAAMTAAoKVSJ3AgD4AgATAAoKVSJ3AgD4AgAUAAMKCgyQGAGrAAAAAA==.',
Ec='Echø:BAAANQADCgUIBQAAAA==.',
Ed='Edrency:BAAANQADCgYIBgAAAA==.',
Ef='Eferis:BAAANQAECggIDgAAAA==.',
El='Elderdorje:BAABNQAECn9NAAMFAAoKdh48BQA/AwAFAAoKdh48BQA/AwAGAAoKXge0OADIAAAAAA==.Elixe:BAAANQAECgEIAgAAAA==.Elmersglue:BAAANQAECgEIAQAAAA==.Elondre:BAABNQAECn9OAAIQAAoKsCPSAwDZAwAQAAoKsCPSAwDZAwAAAA==.',
En='Enjikoma:BAAANQADCgEIAQAAAA==.',
Ev='Evangeliné:BAAANQAECgcIDgABNQAECgcIEwAEAAAAAA==.',
Ex='Execfive:BAAANQADCgIIAQAAAA==.',
Fe='Femboi:BAABNQAECn9IAAIKAAoKnh5YCgA1AwAKAAoKnh5YCgA1AwAAAA==.',
Fi='Firecracker:BAAANQAECgYIEAAAAA==.',
Fo='Fortwooh:BAAANQADCgcIEwAAAA==.',
Fr='Freshlight:BAAANQAECgUIDAABNQAFFAUIEQAFAKgSAA==.',
Fu='Fuurak:BAAANQAFFAEIAQAAAA==.',
Ga='Gado:BAAANQAECgUIBAABNQAFFAUIDQAJAJcLAA==.Galatea:BAACNQAFFH8KAAIVAAQK1RLsFADTAAAVAAQK1RLsFADTAAA1AAQKf1gAAhUACgq2I0AvAAwDABUACgq2I0AvAAwDAAAA.Galifen:BAABNQAECn9QAAIBAAoKfSbBAQDjAwABAAoKfSbBAQDjAwAAAA==.Gameplan:BAAANQADCgYICAAAAA==.Gank:BAABNQAECn8vAAIWAAoKoSKuBACLAwAWAAoKoSKuBACLAwAAAA==.Gardener:BAAANQABCgIIBAAAAA==.',
Gh='Ghreen:BAAANQAECgYICQAAAA==.',
Gi='Gigathreat:BAAANQAECgEIAgAAAA==.Gilgahmesh:BAABNQAECn8kAAIRAAcK0A31NAA9AQARAAcK0A31NAA9AQAAAA==.',
Gn='Gnomegrown:BAABNQAECn8kAAIBAAgK6wwOOQA5AQABAAgK6wwOOQA5AQAAAA==.',
Go='Gothika:BAAANQADCgIIAgAAAA==.Goy:BAAANQAECgcIAgAAAA==.',
Gr='Grainbelt:BAAANQAECggIEgAAAA==.Gru:BAAANQAECgcIBwAAAA==.',
Gy='Gyrux:BAAANQAECgEIAwAAAA==.',
Ha='Halyer:BAAANQADCggIGwAAAA==.Hamalainen:BAABNQAECn8lAAMXAAoKiBIgBgDKAQAXAAkKHRMgBgDKAQALAAkKuwqD0QBeAQABNQAFFAUIEQAFAKgSAA==.Harrydresden:BAAANQABCgIIBAAAAA==.Havøc:BAAANQAECgMIAwAAAA==.',
He='Helioboops:BAAANQADCggIEwAAAA==.',
Ho='Hobbz:BAACNQAFFH8MAAIVAAYK+hQDDgBrAQAVAAYK+hQDDgBrAQA1AAQKf0sAAhUACgpJJQUJAFADABUACgpJJQUJAFADAAAA.',
Il='Illandros:BAABNQAECn8qAAIIAAcKyBCRKAAoAQAIAAcKyBCRKAAoAQAAAA==.',
In='Inspire:BAACNQAFFH8PAAIYAAYKyBKhBwCBAQAYAAYKyBKhBwCBAQA1AAQKfywAAhgACgopI2cJAC8DABgACgopI2cJAC8DAAAA.',
Is='Isinia:BAAANQADCgEIAQAAAA==.Isira:BAAANQAECgcICQAAAA==.',
Ja='Jaína:BAAANQAECgIIBgABNQAECgYIEgAEAAAAAA==.',
Jc='Jcvd:BAAANQADCgYICwABNQAFFAUIEQAFAKgSAA==.',
Je='Jelina:BAABNQAECn8aAAMVAAcKuQeU7gDvAAAVAAcKuQeU7gDvAAARAAEKAABCewAAAAAAAA==.',
Ji='Jiren:BAACNQAFFH8RAAIFAAUKqBItBABrAQAFAAUKqBItBABrAQA1AAQKfz0AAwUACgpMIMAJAO4CAAUACgpMIMAJAO4CAAYABAr2BiZJAG8AAAAA.',
Jo='Johnson:BAABNQAECn8YAAIZAAkKDxSIEQAOAgAZAAkKDxSIEQAOAgAAAA==.Joran:BAABNQAECn8XAAIVAAYKqQnA+QArAQAVAAYKqQnA+QArAQAAAA==.',
Kr='Kro:BAAANQAECgEIAwAAAA==.',
La='Laststop:BAAANQADCgYIBQAAAA==.',
Le='Leanea:BAAANQAECgIIAwAAAA==.',
Li='Liera:BAABNQAECn8iAAINAAgKdxGuNAA7AQANAAgKdxGuNAA7AQAAAA==.Lightsac:BAAANQADCgYIBwAAAA==.Limmywinks:BAAANQAECgIIAgAAAA==.',
Ll='Lloydlei:BAAANQAECgcIEAAAAA==.',
Lu='Luminå:BAABNQAECn8sAAIPAAoKOR1tBADkAgAPAAoKOR1tBADkAgAAAA==.',
['Lå']='Låte:BAAANQADCgcIDQAAAA==.',
Ma='Maibisan:BAABNQAECn9nAAMOAAoKaSY4AQDsAwAOAAoKaSY4AQDsAwAKAAgKBSJCHgBfAgAAAA==.Malificent:BAAANQAECgMIBAAAAA==.',
Mc='Mchack:BAAANQAECggICAAAAA==.',
Me='Metaevoker:BAABNQAECn9TAAIaAAoK8xzjBABsAgAaAAoK8xzjBABsAgAAAA==.',
Mo='Monawah:BAABNQAECn8iAAILAAgKJwv5jADwAQALAAgKJwv5jADwAQAAAA==.Mookong:BAAANQADCgYIBwABNQAECgQIBAAEAAAAAA==.Moonsliver:BAAANQAECgMICgAAAA==.Moorf:BAABNQAECn8jAAMQAAoKvw8JRADsAQAQAAkKdhEJRADsAQACAAUKBATQvAB9AAAAAA==.Morff:BAABNQAECn8bAAMaAAcKEwv/HwBWAQAaAAcKEwv/HwBWAQAbAAEK+ggpPAAlAAAAAA==.Motleychew:BAAANQAECgEIAQAAAA==.',
My='Mystwolf:BAAANQAECgUJCgAAAA==.',
Ne='Ned:BAAANQADCgMIAwABNQAECgYIEgAEAAAAAA==.',
Ni='Nightember:BAAANQAECgEIAQABNQAECgoKTQAFAHYeAA==.Nightski:BAABNQAECn8pAAIYAAoKUxUcFQBjAgAYAAoKUxUcFQBjAgAAAA==.Nizzari:BAAANQAECgMIBgABNQAFFAUIDQAJAJcLAA==.',
No='Nobuseri:BAABNQAECn8dAAIcAAoKcgtYSgC9AQAcAAoKcgtYSgC9AQAAAA==.Nothalyer:BAABNQAECn9CAAMbAAoKuQcsGQBLAQAbAAoKuQcsGQBLAQAJAAgKMQZ2DgDqAAAAAA==.',
['Nå']='Nåtrii:BAAANQAECgEIAQABNQAECggIGgAbAJ4IAA==.',
Ob='Obliviora:BAAANQADCgYIBgAAAA==.',
Og='Ogdi:BAAANQAECgYIEgAAAA==.',
Ol='Olaria:BAAANQADCgMIAwAAAA==.',
Oo='Ookook:BAAANQAECggICAABNQAECgoKIQASANESAA==.',
Or='Orwasitgarp:BAAANQADCgYIBgABNQAECgUIDwAEAAAAAA==.Orwasitme:BAAANQAECgUIDwAAAA==.Orwasitmii:BAAANQADCgMJAwABNQAECgUIDwAEAAAAAA==.',
Pa='Paladinii:BAAANQAECgUIBQAAAA==.',
Ph='Philonk:BAABNQAECn8jAAIGAAoKbRC6JgDtAQAGAAoKbRC6JgDtAQAAAA==.',
Pj='Pjxyo:BAABNQAECn8bAAMMAAgKlxpiOQCtAAALAAgK6RgppQBNAQAMAAQKmA1iOQCtAAAAAA==.',
Po='Polytots:BAACNQAFFH8SAAMQAAcKZg/RDgBiAQAQAAcKZg/RDgBiAQACAAIKcwkNJwCQAAA1AAQKf1AAAxAACgreJP4BAMgDABAACgreJP4BAMgDAAIAAwrrErzBAHQAAAAA.',
Ps='Psycototem:BAAANQAECgMICAAAAA==.',
Ra='Ragñar:BAAANQAECgUIBQAAAA==.Razering:BAAANQAECgEIAQAAAA==.Razius:BAAANQAECggIDgAAAA==.',
Re='Rebexha:BAABNQAECn8ZAAMPAAYKUwreQgC5AAAPAAQKCwjeQgC5AAAdAAYKeQeCxgCxAAAAAA==.Replayjade:BAAANQADCgEIAQAAAA==.',
Ri='Ricklepick:BAABNQAECn8WAAMYAAkK5R2XDgDFAgAYAAkK5R2XDgDFAgAeAAEKAAA1QAA6AAABNQAFFAUIEQAFAKgSAA==.',
Ro='Romaeus:BAAANQADCgYIBwAAAA==.',
Ru='Ruskie:BAAANQADCgEIAQAAAA==.',
Ry='Ryzenther:BAAANQAECgIJBAAAAA==.',
['Rà']='Ràgnar:BAAANQAECgMIAgAAAA==.Ràgñar:BAAANQADCgYIEQAAAA==.',
Sa='Sanctis:BAAANQADCgYIBgAAAA==.',
Sc='Scarpa:BAAANQAECgEIAQABNQAECgoKSAABABEaAA==.Scathclipe:BAABNQAECn8rAAMWAAkK5BaELgAqAgAWAAkKRxSELgAqAgAfAAgKvxT/CAAEAgAAAA==.',
Se='Sealedfate:BAAANQAECgEIBAAAAA==.Seancodi:BAAANQAECgEIAQABNQAFFAcIFwAKAEEZAA==.Senomage:BAABNQAECn8nAAMgAAoKcyJbNgAcAwAgAAoKcyJbNgAcAwAhAAMK/R35HwDqAAAAAA==.Serphentos:BAAANQABCgIIAgAAAA==.',
Sh='Shasato:BAACNQAFFH8GAAIiAAIKNhJwBgCAAAAiAAIKNhJwBgCAAAA1AAQKfzUAAyIACgqsIAcGADMDACIACgqsIAcGADMDAAEABApUDPJgAI8AAAAA.Shazrast:BAAANQADCgQIBAAAAA==.Shockss:BAAANQAECgYIDQAAAA==.',
Si='Sidie:BAAANQADCgMIAwAAAA==.Sindora:BAAANQADCgEIAQAAAA==.Sizouze:BAABNQAECn89AAIHAAoKvw9jXQCzAQAHAAoKvw9jXQCzAQAAAA==.',
Sk='Skeeter:BAAANQADCgYIBgABNQAECgoKKwAPAO8XAA==.Skyepic:BAACNQAFFH8jAAMDAAgKixqXAgCAAgADAAgKixqXAgCAAgARAAEKTgWlEQA+AAA1AAQKfycAAgMACgpyJRQBAOMDAAMACgpyJRQBAOMDAAAA.Skylight:BAAANQAECggIDAAAAA==.',
Sn='Sneakfu:BAABNQAECn86AAMWAAkKnBZbMwAPAgAWAAgKjxBbMwAPAgAcAAkKqxUMRgDNAQAAAA==.Snugwalnut:BAACNQAFFH8RAAIQAAcKtg7gCADDAQAQAAcKtg7gCADDAQA1AAQKfzMAAhAACgpoIYg0AI0CABAACgpoIYg0AI0CAAAA.',
So='Soejoedi:BAABNQAECn9IAAIBAAoKERp9FgBPAgABAAoKERp9FgBPAgAAAA==.Sorrowin:BAAANQABCgIIAgAAAA==.',
Sp='Spicyburrito:BAAANQAECgIIAgAAAA==.',
St='Stitchzpls:BAAANQAECgIIBQAAAA==.',
Su='Sunraku:BAAANQAECgQIAwAAAA==.',
Ta='Taintedrush:BAACNQAFFH8OAAIjAAYKoBJXAQA+AQAjAAYKoBJXAQA+AQA1AAQKfzoAAiMACgoXHRwDANMCACMACgoXHRwDANMCAAAA.Takuan:BAAANQAECgIIAgAAAA==.Tarhostamir:BAAANQAFFAEIAQAAAA==.Taurup:BAAANQADCgYIEwABNQAFFAUIDQAJAJcLAA==.Tazz:BAABNQAECn8kAAMLAAoKKwUzqgBCAQALAAoKKwUzqgBCAQAMAAEKAABwoAAaAAAAAA==.',
Te='Teenjus:BAAANQADCggIFgAAAA==.',
Th='Thaluus:BAAANQADCgUIDQAAAA==.Thanossnap:BAAANQABCgQIBgABNQAECgoKTQAFAHYeAA==.Thaysinga:BAABNQAECn82AAINAAkKaRUrGQANAgANAAkKaRUrGQANAgAAAA==.Thelandlord:BAAANQAECgIIAwAAAA==.Thunderblast:BAABNQAECn8YAAIUAAYKxhi3tACZAQAUAAYKxhi3tACZAQAAAA==.Thuss:BAAANQADCgQIBAAAAA==.',
To='Totemtosser:BAAANQAECgEIAQAAAA==.',
Tr='Trollor:BAAANQAECgEIAgAAAA==.',
Ut='Utzon:BAAANQAECgIIAwABNQAECgoKSAABABEaAA==.',
Va='Vaedan:BAAANQADCgcIEwAAAA==.Valkyrrie:BAAANQADCgcICAABNQADCggIGwAEAAAAAA==.Vander:BAABNQAECn8ZAAMHAAYKkh/LVADSAQAHAAYKkh/LVADSAQAIAAEKAABnjwAbAAAAAA==.Vannder:BAAANQAECgEIBQABNQAECgYIGQAHAJIfAA==.Vayper:BAABNQAECn9SAAQIAAoKNiLDBgBsAwAIAAoKNiLDBgBsAwAHAAIK4gop4wB/AAAkAAEK8gRELwAmAAAAAA==.Vaypshawk:BAAANQADCggIFAABNQAECgoKUgAIADYiAA==.',
Ve='Veins:BAAANQAECgQIBQAAAA==.',
Vi='Viigo:BAAANQABCgQIBAAAAA==.',
['Vë']='Vënöm:BAAANQAECgcICAABNQAECgoKLAAPADkdAA==.',
Wa='Waggo:BAABNQAECn8hAAICAAcKrBAWgwCdAQACAAcKrBAWgwCdAQAAAA==.Waken:BAAANQAECgcICQAAAA==.Warm:BAAANQAFFAEIAQAAAA==.Waterboy:BAAANQADCgcIDAABNQADCgUIBgAEAAAAAA==.',
We='Weemsy:BAAANQADCgYIBgAAAA==.Wellmet:BAAANQAECgEIAwAAAA==.',
Wi='Wildfire:BAACNQAFFH8KAAIXAAcKDRxFAAA9AgAXAAcKDRxFAAA9AgA1AAQKf04AAhcACgrSJhQAAJoDABcACgrSJhQAAJoDAAAA.',
Wo='Wolfhammer:BAABNQAECn9FAAIZAAoKex1oBwBlAgAZAAoKex1oBwBlAgAAAA==.',
Wr='Wreckadin:BAABNQAECn8oAAIVAAoK5B3GKwClAgAVAAoK5B3GKwClAgAAAA==.',
Ya='Yaztraz:BAABNQAECn86AAQQAAoKmBwUPwBkAgAQAAoKmBwUPwBkAgACAAcKig2ZggD0AAAlAAEKFQepNQAwAAAAAA==.',
Ye='Yellowflag:BAAANQAECggIEQABNQAFFAkJLAASAHEgAA==.',
Za='Zarturion:BAAANQAECgEIBgAAAA==.',
Zo='Zod:BAACNQAFFH8NAAMJAAUKlwtxCAC3AAAJAAUKlwtxCAC3AAAaAAEKQQJCEQAyAAA1AAQKf0oAAwkACgoJGcYEALACAAkACgoJGcYEALACABoABgpqDo4TAOoAAAAA.',
['Às']='Àsh:BAABNQAECn8iAAIHAAoKfhGGXwACAgAHAAoKfhGGXwACAgAAAA==.',
['Év']='Évangeline:BAAANQAECgcIEwAAAA==.',
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

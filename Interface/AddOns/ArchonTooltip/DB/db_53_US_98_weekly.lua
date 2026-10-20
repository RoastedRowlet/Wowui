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

local lookup = {'Druid-Balance','Warrior-Protection','Mage-Arcane','Paladin-Retribution','Paladin-Holy','Paladin-Protection','Evoker-Preservation','Shaman-Restoration','DeathKnight-Frost','DeathKnight-Blood','Hunter-Marksmanship','Unknown-Unknown','Warlock-Affliction','Warlock-Demonology','Monk-Windwalker','Shaman-Elemental','Monk-Brewmaster','Hunter-BeastMastery','Warrior-Arms','Druid-Restoration','Priest-Discipline','Priest-Holy','Warlock-Destruction','Rogue-Subtlety','Rogue-Assassination','DeathKnight-Unholy','Warrior-Fury','DemonHunter-Vengeance','DemonHunter-Havoc','Mage-Frost','Druid-Feral','DemonHunter-Devourer','Shaman-Enhancement','Evoker-Devastation','Priest-Shadow','Evoker-Augmentation','Hunter-Survival','Monk-Mistweaver','Druid-Guardian',}
local provider = {region='US',realm='Frostmane',name='US',type='weekly',zone=53,date='2026-10-20',data={Ab='Abaz:BAAANQAECgQIBgAAAA==.Aberdus:BAABNQAECn8hAAIBAAgKQRERQwDpAQABAAgKQRERQwDpAQAAAA==.Abysswalker:BAAANQADCgQIBAAAAA==.',
Ac='Accalon:BAABNQAECn8aAAICAAgK5CNCBwDpAgACAAgK5CNCBwDpAgAAAA==.',
Ad='Adaam:BAAANQADCgIIAgAAAA==.Advacus:BAACNQAFFH8JAAIDAAMKkR1BMAANAQADAAMKkR1BMAANAQA1AAQKfyQAAgMACQogJNsUAIADAAMACQogJNsUAIADAAAA.',
Ag='Agamar:BAAANQAECgEIAQAAAA==.Ageina:BAAANQADCggICAABNQAFFAQIBwAEABgeAA==.Agnostec:BAAANQADCgIIAwAAAA==.',
Ak='Akrama:BAABNQAECn8jAAMFAAkKih3dBACSAgAFAAkKih3dBACSAgAEAAEKAABX1AEbAAAAAA==.',
Al='Alatáriel:BAAANQAECgIIAQAAAA==.Alectrona:BAAANQADCgYICAAAAA==.Althenot:BAAANQADCgcIDwAAAA==.',
Am='Amari:BAAANQADCgEIAQAAAA==.Amegoracy:BAABNQAECn8WAAQGAAcKhxN3NwAuAQAEAAYKdhOo1gBuAQAGAAUKxxN3NwAuAQAFAAIKlgJ2GQFBAAAAAA==.',
An='Andalorian:BAAANQAECgMJAwAAAA==.Anderthel:BAAANQAECgIIBAAAAA==.Anruu:BAAANQAECgcIDgAAAA==.',
Ar='Araleth:BAAANQADCggIGAAAAA==.Aratol:BAAANQAECgYICAABNQAECgoKKQAHADwUAA==.Archolaoch:BAABNQAECn8tAAIGAAoKPhRsBQCsAQAGAAoKPhRsBQCsAQAAAA==.Arconite:BAAANQADCgQIBQABNQAECgkJGAAIAAwVAA==.Arizonatea:BAAANQAECgEIAQAAAA==.Arkthurus:BAAANQAECgQIBQAAAA==.',
As='Ashenknight:BAAANQADCgEJAQAAAA==.Ashijin:BAACNQAFFH8KAAMEAAUKiRANFAAYAQAEAAUKiRANFAAYAQAFAAEKeQFrFgA5AAA1AAQKfyUAAwQACgrKGVFjAHACAAQACgrKGVFjAHACAAUAAQoCASM9ARIAAAAA.Astei:BAAANQADCgUIBQAAAA==.',
At='Athelos:BAAANQAECgEIAQAAAA==.Atroce:BAABNQAECn8xAAMJAAoKtiLrBQD+AQAKAAgK8hxEKwBtAgAJAAkKxyPrBQD+AQAAAA==.',
Au='Aura:BAAANQAECgYIDwAAAA==.Auxilium:BAAANQADCggIDgAAAA==.',
Aw='Awnen:BAAANQAECgUIDAAAAA==.',
Ax='Axes:BAAANQAECgIIAgAAAA==.Axkicker:BAABNQAECn82AAILAAgKzxWLJgAXAgALAAgKzxWLJgAXAgAAAA==.',
Ay='Aystic:BAAANQAECgEIAQABNQAECggICwAMAAAAAA==.',
Ba='Balethar:BAAANQAECgUICgABNQAECgoKKAAGAKIcAA==.Ballador:BAAANQAECggIDgAAAA==.Balluh:BAAANQAECgYIEAAAAA==.Balzluzzak:BAABNQAECn8jAAMNAAoKSgkLDQCMAQANAAoKSgkLDQCMAQAOAAUKmAVrBAHDAAAAAA==.Baughter:BAAANQABCgcICwAAAA==.',
Be='Beeffisting:BAAANQADCgEIAQAAAA==.Beetledeww:BAAANQADCgQIBAAAAA==.Beetledont:BAAANQADCgYIBgAAAA==.Beezbonk:BAAANQAECggICAAAAA==.Bellemorte:BAAANQABCgQIBwAAAA==.Bellmage:BAABNQAECn8nAAIDAAkKiRq5FADDAQADAAkKiRq5FADDAQAAAA==.Belttoash:BAAANQAECgQICAAAAA==.Beneficiary:BAAANQADCgYIBgAAAA==.Bestricer:BAACNQAFFH80AAIPAAoK/BxAAACQAwAPAAoK/BxAAACQAwA1AAQKfzEAAg8ACgqUJhgCAMIDAA8ACgqUJhgCAMIDAAAA.Bevis:BAABNQAECn8jAAIOAAoKdx8oEABRAwAOAAoKdx8oEABRAwABNQAFFAQIDQAQALEeAA==.',
Bi='Bigmayex:BAABNQAECn8jAAIRAAkKRiShAwBTAwARAAkKRiShAwBTAwAAAA==.Bilmuri:BAABNQAECn8hAAMSAAoKDB9BJAAGAwASAAkK9yBBJAAGAwALAAUKiRX6SwAEAQAAAA==.Bippot:BAABNQAECn8rAAIEAAkKkB+nOQDqAgAEAAkKkB+nOQDqAgAAAA==.',
Bl='Blakangus:BAAANQADCgcICAABNQAECgoKIQALAJwNAA==.Blastetta:BAAANQAECgIIAgABNQAFFAUIEAATAGENAA==.Bloodybill:BAAANQADCgUIBQAAAA==.Blort:BAAANQADCggICAAAAA==.',
Bo='Bombadormu:BAAANQADCgcIBwAAAA==.Bonezs:BAABNQAECn8tAAIUAAoKNSErBwBQAwAUAAoKNSErBwBQAwAAAA==.Boredfordays:BAAANQAECgEIAQAAAA==.Borislav:BAAANQADCggIEQAAAA==.Bossvega:BAAANQAECgEIAQAAAA==.',
Br='Bruhkakke:BAAANQAECggIBAABNQAFFAUIDAAIAIwJAA==.Brutagon:BAAANQADCgQIBAABNQAECgYIEAAMAAAAAA==.',
Bu='Bucon:BAAANQADCgYIDAAAAA==.Bufferbug:BAAANQADCgEIAQAAAA==.Bugbear:BAAANQAECgUIBQAAAA==.Bumbly:BAABNQAECn8ZAAMVAAkKeBM2DgBMAQAVAAYKkRA2DgBMAQAWAAgKSw6/VgDIAAAAAA==.Bunny:BAAANQADCgMIAwAAAA==.Bushybrowsy:BAABNQAECn85AAQNAAoK6w/GBwAbAgANAAkKQRHGBwAbAgAOAAMKYgWzMAFaAAAXAAEK2gM1egAzAAAAAA==.Buttermeupz:BAABNQAECn8kAAIFAAoKnxNWTwAuAgAFAAoKnxNWTwAuAgAAAA==.Buttsnorkle:BAAANQAECgIIAgAAAA==.',
['Bá']='Bámboo:BAAANQAECgQICAAAAA==.',
Ca='Cacho:BAAANQAECgcIEQAAAA==.Cactuss:BAAANQAECgUIDwABNQAECgoKKAADANQIAA==.Caothand:BAAANQAECgcIEAAAAA==.',
Cc='Ccyll:BAAANQADCgcIEAAAAA==.',
Ce='Celindri:BAAANQADCgcIBwAAAA==.Cerridwen:BAAANQABCgIIAgAAAA==.',
Ch='Chazandi:BAAANQADCgQIBAABNQAECgkJGQAWABATAA==.Chazpriest:BAABNQAECn8ZAAIWAAkKEBMmCwAyAgAWAAkKEBMmCwAyAgAAAA==.Chazzbadgurl:BAAANQAECgcICwABNQAECgkJGQAWABATAA==.Chazzie:BAAANQAECggIDwABNQAECgkJGQAWABATAA==.Chexmix:BAABNQAECn8ZAAMYAAYKtgyZLQBUAQAYAAYKxQuZLQBUAQAZAAQKMAvaewDDAAAAAA==.Chicho:BAAANQAECgMIAwAAAA==.Chomboslice:BAAANQAECggIEQAAAA==.',
Ci='Cinnamon:BAABNQAECn8xAAIWAAoKpR27DgAGAgAWAAoKpR27DgAGAgAAAA==.',
Cm='Cmil:BAACNQAFFH8RAAMFAAYKphW3DACUAQAFAAYKphW3DACUAQAEAAEKwgFUNQBAAAA1AAQKfywABAUACgrBHw4aAA8DAAUACgrBHw4aAA8DAAQABwo+DirTAHUBAAYAAgqDF0teAGEAAAAA.',
Co='Coffeegin:BAAANQADCgMIAwAAAA==.',
Cr='Crittingbull:BAABNQAECn8YAAIQAAoKcxF0DQCnAQAQAAoKcxF0DQCnAQAAAA==.Cruiddeath:BAABNQAECn8UAAIaAAYKww66HgD1AAAaAAYKww66HgD1AAABNQAECgoKKwAbANIKAA==.',
Cu='Curserodlock:BAABNQAECn8rAAMbAAoK0gq0EQCJAQAbAAgKIgy0EQCJAQATAAcKaAaCdgCwAAAAAA==.',
Cy='Cyanide:BAAANQAECgYICwAAAA==.',
Da='Dabbinshamin:BAAANQADCggIDwAAAA==.Dads:BAACNQAFFH8VAAIQAAcKRxj7AwBeAgAQAAcKRxj7AwBeAgA1AAQKfyAAAxAACgo9ISsUAFEDABAACgo9ISsUAFEDAAgAAwpKAeP+AGwAAAAA.Daedra:BAABNQAECn8VAAIEAAgKhw3AzwB8AQAEAAgKhw3AzwB8AQABNQAECgoKIQALAJwNAA==.Daillin:BAAANQADCgEIAQAAAA==.Dakadakadaka:BAABNQAECn8oAAMLAAkKdR7EDAApAQALAAkKnx3EDAApAQASAAEKiR2srgBXAAAAAA==.Darcdk:BAAANQAECgUICwABNQAFFAYIFAAFACQNAA==.Darcevoker:BAAANQADCgcIBwABNQAFFAYIFAAFACQNAA==.Darcpaladin:BAACNQAFFH8UAAIFAAYKJA26CQDEAQAFAAYKJA26CQDEAQA1AAQKfyoAAgUACgpwF4gpAMICAAUACgpwF4gpAMICAAAA.Darcpriest:BAAANQAECgQIBQABNQAFFAYIFAAFACQNAA==.Darkrune:BAAANQAECgIIAwAAAA==.Darkschneide:BAABNQAECn8XAAIOAAkK1BCSbQAWAgAOAAkK1BCSbQAWAgAAAA==.Darthboo:BAAANQAECgQIBgAAAA==.Darthknight:BAAANQAECgUIBgABNQAECgoKKgAEAKodAA==.Darthtemplar:BAABNQAECn8qAAQEAAoKqh3lNAD5AgAEAAoKqh3lNAD5AgAGAAQKQw25HACrAAAFAAEKBgcPJwEuAAAAAA==.',
De='Deathbug:BAAANQADCggIEQAAAA==.Deckaye:BAAANQAECgUICQABNQAECgUICgAMAAAAAA==.Deimoes:BAABNQAECn8VAAISAAgKSBQ8GgCwAQASAAgKSBQ8GgCwAQAAAA==.Demodorn:BAACNQAFFH8TAAIcAAUKVAKhAQCSAAAcAAUKVAKhAQCSAAA1AAQKfzYAAhwACgrqCdURAJQBABwACgrqCdURAJQBAAAA.Demyst:BAACNQAFFH8QAAIIAAYK7xVGCwCZAQAIAAYK7xVGCwCZAQA1AAQKfycAAwgACgoGHgkiAOACAAgACgoGHgkiAOACABAAAgo+DmwVAWIAAAAA.Demön:BAAANQAECgMIAwAAAA==.Dewwarrior:BAAANQAECgUIDwAAAA==.Dezeraz:BAEANQAECgYIBgABNQAFFAYIHQAWAG8dAA==.',
Dh='Dhecaye:BAAANQAECgUICgAAAA==.',
Di='Diomedes:BAAANQABCgIIAgAAAA==.Disengage:BAAANQAECgUICAABNQAFFAYICwADALEQAA==.',
Do='Dohdan:BAAANQAECgUIAgAAAA==.Donkey:BAABNQAECn8pAAIFAAkKXx++JQDTAgAFAAkKXx++JQDTAgAAAA==.Donmega:BAAANQADCggILwAAAA==.Dougalleone:BAACNQAFFH8OAAMZAAYKfh2yBQDQAQAZAAUK4huyBQDQAQAYAAMKNBhoBAAPAQA1AAQKfyAAAxkACgqXH7ENABYDABkACQpnIrENABYDABgABwq+Ft0oAH4BAAAA.Dougallmaki:BAAANQAECgIIAgAAAA==.',
Dr='Drekkwarr:BAAANQAECgEIAQABNQAECgkJKwAQAGccAA==.Drentalth:BAAANQADCgEIAQAAAA==.Drezzakzdh:BAAANQAECgYIDAABNQAECgYIDgAMAAAAAA==.Drezzakzz:BAAANQAECgYIDgAAAA==.Drezzpally:BAAANQADCgMIAwAAAA==.',
Du='Dugren:BAAANQAECgIIAQAAAA==.Duracreate:BAAANQAECgUICgAAAA==.',
Ea='Eamil:BAAANQADCgcIBwAAAA==.',
Ek='Ekaterin:BAACNQAFFH8MAAIDAAUK2xwHCwADAQADAAUK2xwHCwADAQA1AAQKfzIAAgMACgpBHmgnAEQDAAMACgpBHmgnAEQDAAAA.Ekewa:BAAANQAECgQIBAAAAA==.',
El='Elaidine:BAABNQAECn8sAAMcAAgKoh7oAQDOAQAcAAgKoh7oAQDOAQAdAAEKRgELpgAMAAAAAA==.Electraknub:BAAANQADCgYICwAAAA==.Electroh:BAAANQAECgYIDgAAAA==.Eliseda:BAAANQAECgQIBgABNQAECgkJJAAIAIAWAA==.',
Em='Emerald:BAAANQABCgYICwAAAA==.',
Ev='Evilnapkin:BAAANQAECgQICAAAAA==.Evion:BAABNQAECn8fAAISAAcK5xmxdAAnAgASAAcK5xmxdAAnAgAAAA==.Evoke:BAAANQAECgcICwAAAA==.',
Fa='Falconsha:BAAANQAECgIIBgAAAA==.Fattynattyy:BAAANQADCgYIBgAAAA==.',
Fe='Feldamned:BAAANQADCgQIBAAAAA==.Fendis:BAAANQADCggIDgABNQAECgkJNgADANQcAA==.',
Fi='Fiercia:BAAANQAECgUICgABNQAECgoKLQAaAGckAA==.Firefrost:BAABNQAECn9BAAMeAAkKbyP5AACcAwAeAAkKbyP5AACcAwADAAEKgQaBxwE0AAAAAA==.Firescrotum:BAABNQAECn81AAIQAAoKxRMPHQBIAQAQAAoKxRMPHQBIAQAAAA==.',
Fl='Flashquinaz:BAAANQADCgYIBgAAAA==.',
Fo='Fourimborniy:BAAANQAECggIEgAAAA==.',
Fr='Freebandz:BAAANQAECgEIAQAAAA==.Frenzi:BAAANQADCgYICQAAAA==.',
Fu='Fundipme:BAAANQAECgQIBAABNQAFFAcIEgAGAJ4VAA==.',
['Fá']='Fáelen:BAABNQAECn8gAAIfAAoKuByZBQAhAwAfAAoKuByZBQAhAwAAAA==.',
Ga='Galasmina:BAAANQAECgYIDAAAAA==.Galaxius:BAAANQADCgEIAQABNQAECgkJGAAIAAwVAA==.Ganda:BAAANQADCgEJAQAAAA==.Gangactivity:BAAANQADCgUIBQABNQAECgoKPQAPAD8lAA==.Garm:BAABNQAECn8gAAIDAAkKGSMnHABmAwADAAkKGSMnHABmAwAAAA==.Gavinrad:BAAANQAECgcIDgAAAA==.',
Ge='Generaname:BAAANQADCgcJDQAAAA==.Generanancy:BAAANQADCgIJAgAAAA==.Gep:BAAANQAECgQIBgABNQAECgcIGAAgAPkeAA==.',
Gh='Ghostshadow:BAAANQAECgIIBAAAAA==.',
Gi='Gilene:BAAANQADCggIEQAAAA==.Girthfury:BAACNQAFFH8MAAIIAAUKjAk1EABNAQAIAAUKjAk1EABNAQA1AAQKfxUAAxAACgriGolAAHMCABAACQq6HIlAAHMCAAgAAwqZE25/AFgAAAAA.',
Gl='Glaalinix:BAAANQADCgMIBgAAAA==.',
Gn='Gnew:BAAANQADCgUICgAAAA==.Gnumchuck:BAABNQAECn8XAAICAAgK4Qt2HAB2AQACAAgK4Qt2HAB2AQAAAA==.',
Go='Goat:BAAANQAECgMIAwAAAA==.Goku:BAABNQAECn8tAAMIAAoK7B8uEwAxAwAIAAoK7B8uEwAxAwAQAAEKAACgSAEqAAAAAA==.Goodman:BAABNQAECn8jAAMEAAkKZBLAGADAAQAEAAkKZBLAGADAAQAGAAIKsg+MZABOAAAAAA==.Goom:BAAANQAECggIEgABNQAFFAcIGgAPAOoXAA==.Goomei:BAACNQAFFH8aAAIPAAcK6hdbAgBkAgAPAAcK6hdbAgBkAgA1AAQKfyIAAg8ACgoqIAoXAJQCAA8ACgoqIAoXAJQCAAAA.Goomkin:BAACNQAFFH8NAAMBAAYKhAUSGADqAAABAAQKaAMSGADqAAAUAAUKUQqWBQDQAAA1AAQKfyMAAwEACgosFpkxAFYCAAEACQo3GJkxAFYCABQABgopG5QzAH4BAAE1AAUUBwgaAA8A6hcA.Gordanramsey:BAAANQADCgUIBQAAAA==.Gorok:BAAANQAECgUIBAAAAA==.',
Gr='Gravymonk:BAABNQAECn8ZAAIPAAkKYgg3MwB8AQAPAAkKYgg3MwB8AQAAAA==.Greatbooty:BAAANQAECgcIEAAAAA==.Gremmi:BAAANQADCgYIBgAAAA==.Grishy:BAAANQAECggICAABNQAFFAYICwADALEQAA==.Grombeefdal:BAAANQAECgIIAgAAAA==.Grosgland:BAAANQAECgEIAQAAAA==.Groundbeéf:BAACNQAFFH8VAAIhAAYK7xlPAQAUAgAhAAYK7xlPAQAUAgA1AAQKfykAAiEACgq0JGAFADUDACEACgq0JGAFADUDAAAA.Grovoath:BAAANQADCgcIDgAAAA==.Grumpypally:BAAANQAECggIBwAAAA==.',
Gu='Guldar:BAAANQADCgEIAQAAAA==.Gurthon:BAAANQADCggIDwAAAA==.',
Ha='Halligan:BAAANQAECgYIEwAAAA==.Hallowfear:BAAANQAECgUIDgABNQAECgcIAwAMAAAAAA==.Handadinite:BAAANQADCgUICAAAAA==.Handysummons:BAABNQAECn8fAAIOAAkKgh9UJABdAQAOAAkKgh9UJABdAQAAAA==.Harie:BAABNQAECn8ZAAIeAAcKaxQlBgA8AQAeAAcKaxQlBgA8AQAAAA==.Harydotter:BAABNQAECn8UAAIOAAcK2gqyPAAWAQAOAAcK2gqyPAAWAQAAAA==.Hawtsoss:BAAANQABCgQIBwAAAA==.',
He='Hein:BAAANQAECgQICAAAAA==.Heiny:BAABNQAECn84AAQKAAoKwiQzAgDRAwAKAAoKUCQzAgDRAwAJAAkKXCBvEwDxAgAaAAYKRyM+NwBKAgAAAA==.Heinyheinyho:BAAANQADCgMIBAABNQAECgoKOAAKAMIkAA==.',
Ho='Hoid:BAAANQAECggICwAAAA==.Holeybeef:BAAANQAECgYIEgAAAA==.Holymoly:BAAANQADCgMIAQABNQAECgkJQQAeAG8jAA==.Holynoodles:BAEBNQAECn8aAAIEAAoKSBuncQBMAgAEAAoKSBuncQBMAgAAAA==.Holytest:BAACNQAFFH8MAAIWAAQKsxx6CABIAQAWAAQKsxx6CABIAQA1AAQKfzIAAhYACgqIH8MWAB4DABYACgqIH8MWAB4DAAAA.Hoofmetoo:BAABNQAECn8cAAMJAAgK2Rv9LQAxAgAJAAgKyhv9LQAxAgAaAAQKJByakADmAAAAAA==.Howboudah:BAAANQADCgcIBwAAAA==.',
Hu='Hulzar:BAABNQAECn8fAAITAAoK1gvvIgB5AQATAAoK1gvvIgB5AQAAAA==.',
Hy='Hypernova:BAAANQAECgUIBQAAAA==.Hypocrisy:BAAANQAECggIEAAAAA==.',
['Hô']='Hôlyblight:BAACNQAFFH8NAAIFAAUKhxuJCwCkAQAFAAUKhxuJCwCkAQA1AAQKfzQAAwUACgrTGCEwAKUCAAUACgrTGCEwAKUCAAQACQqsE/KIABUCAAAA.',
Ib='Ibis:BAAANQAFFAEIAQABNQAFFAMIBQAHAA4EAA==.',
Id='Idotyouto:BAAANQADCgcIBwAAAA==.',
Ih='Iheartdemons:BAEANQAECgEIAQABNQAECgoKGgAEAEgbAA==.',
Il='Ilbryen:BAAANQAECgQIBQABNQAFFAYIEAATAN8WAA==.Illaam:BAAANQADCggIDAAAAA==.Illidrag:BAABNQAECn8XAAIdAAoKZAkcPwDDAQAdAAoKZAkcPwDDAQAAAA==.Ilovejacky:BAAANQADCgcIDQAAAA==.',
Im='Immørtlzed:BAACNQAFFH8YAAIIAAgKciF2AQC4AgAIAAgKciF2AQC4AgA1AAQKfy8AAwgACgq0Je8DAKwDAAgACgq0Je8DAKwDABAAAgpUFZ4CAYoAAAAA.',
In='Inara:BAAANQAECgMIBAABNQAECgkJKgAPAEQYAA==.Insurion:BAAANQAECgQIBgAAAA==.Invective:BAABNQAECn8VAAINAAcKpRHcBAD+AAANAAcKpRHcBAD+AAAAAA==.',
Ir='Ironstorm:BAAANQADCgQIBAAAAA==.',
Iz='Izzyumi:BAAANQADCgYIBgAAAA==.',
Ja='Jarizard:BAACNQAFFH8WAAIHAAYK3Qs2BQAaAQAHAAYK3Qs2BQAaAQA1AAQKfykAAwcACgoaFSQYADoCAAcACgoaFSQYADoCACIAAQrzBxBAACsAAAAA.Jarrie:BAAANQAECgQIBAAAAA==.Jassar:BAAANQAECgEIAgAAAA==.Jaxdk:BAAANQAECgIIAgAAAA==.Jaxek:BAABNQAECn83AAIfAAoKYCLFAQCtAwAfAAoKYCLFAQCtAwAAAA==.Jaxs:BAACNQAFFH8RAAIIAAcK+xBpCQC6AQAIAAcK+xBpCQC6AQA1AAQKfycAAggACgo3HC89AGsCAAgACgo3HC89AGsCAAAA.Jaylen:BAAANQAECgQICQAAAA==.Jaymo:BAABNQAECn8cAAICAAgKFhmFDQBaAgACAAgKFhmFDQBaAgAAAA==.',
Je='Jebke:BAABNQAECn8gAAINAAgKGSJ2AAA+AgANAAgKGSJ2AAA+AgAAAA==.Jeneke:BAAANQAECgIIAgAAAA==.',
Jo='Johnwick:BAAANQADCgQIBAAAAA==.Jopha:BAACNQAFFH8VAAITAAYKfxyyCAAqAgATAAYKfxyyCAAqAgA1AAQKfygAAxMACgr2INYhADEDABMACgr2INYhADEDABsAAQoAAL4qAFwAAAAA.Jophr:BAAANQAECgUICwABNQAFFAYIFQATAH8cAA==.Jore:BAAANQAECgIIAwAAAA==.',
Jp='Jpbruiser:BAABNQAECn88AAIEAAoKtxbjFADVAQAEAAoKtxbjFADVAQAAAA==.',
Ju='Jumpndeath:BAACNQAFFH8MAAIKAAYKcBUNDQCDAQAKAAYKcBUNDQCDAQA1AAQKfyAAAwoACgoCH8MUAAYDAAoACgoCH8MUAAYDAAkAAQoEDTCrADcAAAE1AAUUAggEAAwAAAAA.Jumpnjudge:BAAANQAFFAIIBAAAAA==.Jumpnpray:BAABNQAECn8XAAQVAAkKkRVgCwCLAQAVAAYKeBVgCwCLAQAjAAYKkQ1aPABIAQAWAAUKMhPWmQBHAQABNQAFFAIIBAAMAAAAAA==.Justgetme:BAABNQAECn8oAAMGAAoKohzyCgBLAQAEAAoKwxj+fQAuAgAGAAYKJCXyCgBLAQAAAA==.',
Ka='Kaan:BAAANQADCgEIAQAAAA==.Kaariel:BAAANQADCgYIBgAAAA==.Kabo:BAACNQAFFH8LAAITAAQKfA1BHgAcAQATAAQKfA1BHgAcAQA1AAQKfyoAAhMACgpyF3pRAJUCABMACgpyF3pRAJUCAAAA.Kadela:BAAANQAECgEIAQAAAA==.Kagger:BAACNQAFFH8IAAIEAAIKtx2gCgC+AAAEAAIKtx2gCgC+AAA1AAQKfyMAAgQACgo1IdEfAEQDAAQACgo1IdEfAEQDAAAA.Kardoroth:BAACNQAFFH8LAAIaAAUKFSOkBQDKAQAaAAUKFSOkBQDKAQA1AAQKfyEAAhoACgrKJFIPADwDABoACgrKJFIPADwDAAAA.Karib:BAAANQAECgEIAQABNQAFFAUIDQAaALAeAA==.Karîba:BAACNQAFFH8NAAQaAAUKsB4VBAC6AAAaAAUKsB4VBAC6AAAKAAMKZApBHQCnAAAJAAIKURoZFACeAAA1AAQKfzoABBoACgrdIz8JAHUDABoACQoIJT8JAHUDAAkACAr+INYhAH8CAAoABAocGqmAAPkAAAAA.',
Ke='Keld:BAEBNQAECn8dAAMiAAoKQA9uAgCpAQAiAAoKpA5uAgCpAQAkAAUKXhApEwD+AAAAAA==.Kellienna:BAAANQAECgQIBgABNQAECgoKKgAEAKodAA==.Kelsaz:BAACNQAFFH8SAAQSAAYKWhbcFAAZAQASAAQKexfcFAAZAQALAAMKew7iGAC7AAAlAAEKAACIAgBRAAA1AAQKfyUAAxIACgr+JBUjAAsDABIACgr+JBUjAAsDAAsABgpnGqc+AF0BAAAA.Kelshock:BAAANQAECgEIAgAAAA==.Kelsi:BAABNQAECn8qAAIPAAkKRBiyHQBHAgAPAAkKRBiyHQBHAgAAAA==.Kenný:BAAANQAECgYICQAAAA==.Kerrìgàn:BAACNQAFFH8QAAMdAAUKvRB4CwBpAQAdAAUKvRB4CwBpAQAcAAIKlgr9AwAAAAA1AAQKfz8AAx0ACgpUIHYOADIDAB0ACgpUIHYOADIDABwABQrsGuQSAIABAAAA.Kestral:BAACNQAFFH8FAAIHAAMKDgS0EgCzAAAHAAMKDgS0EgCzAAA1AAQKfxsAAgcACQoRDYEeAOkBAAcACQoRDYEeAOkBAAAA.',
Kh='Khalisi:BAAANQAECgEIAwAAAA==.',
Ki='Kickyboots:BAAANQAECgQIBAABNQAECggIDwAMAAAAAA==.Kilesta:BAAANQADCggICAAAAA==.Kitara:BAAANQADCgIIAgAAAA==.',
Ko='Koochlathom:BAAANQAECgEIAQABNQAECgkJHQAFAEkeAA==.Kookiie:BAACNQAFFH8VAAIdAAYKdBudAwBHAgAdAAYKdBudAwBHAgA1AAQKfygAAh0ACgoDJUAMAEkDAB0ACgoDJUAMAEkDAAAA.Koom:BAAANQAECgMIBAAAAA==.Korgoroth:BAAANQABCgIIAwAAAA==.Kosian:BAAANQAECgIIAwABNQAECgkJNgADANQcAA==.Kosigan:BAAANQADCgUIBQABNQAFFAUIDAADANscAA==.',
Kr='Krepuscular:BAABNQAECn8iAAITAAgKuB1EUwCQAgATAAgKuB1EUwCQAgAAAA==.Kryptiq:BAACNQAFFH8RAAICAAYKqh2JAQDBAQACAAYKqh2JAQDBAQA1AAQKfyIAAgIACgoIJNQCAH8DAAIACgoIJNQCAH8DAAAA.Kryptìq:BAAANQAECgUIBgABNQAFFAYIEQACAKodAA==.',
Ku='Kurisami:BAAANQAECgcIEgAAAA==.',
La='Larielin:BAAANQADCgYIBgAAAA==.Larra:BAACNQAFFH8QAAIWAAYKARUaDwCgAQAWAAYKARUaDwCgAQA1AAQKfyEABBUACgraFVkHAAICABUACQpcD1kHAAICABYABQoeGTRcALsAACMAAQoAAKqCACcAAAAA.',
Le='Leeha:BAAANQAECgIIAQAAAA==.Leman:BAAANQAECgMIAwAAAA==.Lemondonut:BAAANQADCgUIBQAAAA==.Leomessi:BAAANQADCgQIAwABNQAECgoKMQASADQWAA==.Levitas:BAABNQAECn8pAAICAAoK6w8XCgAPAQACAAoK6w8XCgAPAQAAAA==.Leyron:BAABNQAECn8UAAIZAAgKaRRsMAAgAgAZAAgKaRRsMAAgAgABNQAECgoKKgAEAKodAA==.',
Li='Likkhan:BAAANQAECgEIAQAAAA==.Lithel:BAAANQADCggIHgAAAA==.',
Lo='Lockdragoon:BAAANQABCgIIBAAAAA==.Lodbrok:BAAANQABCgQIBAAAAA==.Logics:BAACNQAFFH8HAAIjAAQKshJeBADvAAAjAAQKshJeBADvAAA1AAQKfy8AAyMACgpYIIwNABQDACMACgpYIIwNABQDABYABgoxA/DBANYAAAAA.Longsham:BAAANQADCgUIBgAAAA==.Lostmyvigor:BAAANQAECgQICAAAAA==.Lostvoker:BAABNQAECn8lAAMkAAoKtBG7CAAEAgAkAAoKtBG7CAAEAgAiAAIKYAXyNABmAAAAAA==.',
Lu='Lucarad:BAAANQAECgUIBgAAAA==.Lucivia:BAABNQAECn8hAAINAAgKZRp7BQBqAgANAAgKZRp7BQBqAgAAAA==.Lumafist:BAABNQAECn89AAIPAAoKPyVeAABKAwAPAAoKPyVeAABKAwAAAA==.Lunär:BAAANQAECgYIBgAAAA==.',
['Lè']='Lènneth:BAABNQAECn8vAAMjAAoK/gxjKgDUAQAjAAkKSw5jKgDUAQAWAAcKYxdTfgCeAQAAAA==.',
Ma='Maddelyn:BAACNQAFFH8QAAIDAAcKRxWuBgBYAgADAAcKRxWuBgBYAgA1AAQKfyoAAgMACgowJc0SAIcDAAMACgowJc0SAIcDAAAA.Magewreck:BAAANQAECgUIBgAAAA==.Magicdaddy:BAAANQADCgEIAQAAAA==.Majaer:BAAANQADCgYIBgAAAA==.Mapp:BAABNQAECn8hAAMLAAoK3RJLFADiAAASAAYKxxXYtgCWAQALAAkKXhBLFADiAAAAAA==.Mashanu:BAACNQAFFH8QAAIQAAYKeRNwCwC0AQAQAAYKeRNwCwC0AQA1AAQKfxoAAhAACgqpGwsoAOICABAACgqpGwsoAOICAAE1AAUUBgoQABAAeRMA.Mashpriest:BAAANQADCgIIAgAAAA==.Mazur:BAAANQAECggIDgAAAA==.',
Mc='Mcmonkton:BAAANQADCgIIAgAAAA==.',
Me='Meanssa:BAECNQAFFH8LAAIKAAUKIBqXDACLAQAKAAUKIBqXDACLAQA1AAQKfyQAAgoACgrSGEUqAHMCAAoACgrSGEUqAHMCAAAA.Megamaxamx:BAAANQADCgIIAgAAAA==.Melaan:BAABNQAECn8nAAMUAAgKvRtUBQAKAgAUAAgKvRtUBQAKAgAfAAEKAABSSAApAAAAAA==.Meldatonin:BAAANQAECgIIAgAAAA==.Metaslave:BAAANQAECgIIAQAAAA==.Mewreck:BAAANQADCgIIAgAAAA==.',
Mi='Mindleseye:BAAANQAECggIEAAAAA==.Misosalty:BAABNQAECn9BAAQmAAoK2BrzAQBtAgAmAAoK2BrzAQBtAgAPAAUKqxHDQAARAQARAAMK+BIfIQDXAAAAAA==.',
Mo='Mohjito:BAABNQAECn8dAAImAAkKuRO6CwAZAQAmAAkKuRO6CwAZAQAAAA==.Monica:BAAANQAECgEIAQAAAA==.Moojinbuu:BAAANQAECgQIBwAAAA==.Mooshanu:BAAANQABCgMIBAABNQAFFAYKEAAQAHkTAA==.Mootini:BAAANQAECgEIAQAAAA==.Morguth:BAACNQAFFH8PAAISAAYK8g3ABQADAQASAAYK8g3ABQADAQA1AAQKfxsAAhIACgruHGdDAKECABIACgruHGdDAKECAAAA.Moripally:BAABNQAECn8lAAIEAAoK5SLIBQCQAgAEAAoK5SLIBQCQAgABNQAFFAUIDQAjADohAA==.Moripriest:BAACNQAFFH8NAAIjAAUKOiFTCACKAQAjAAUKOiFTCACKAQA1AAQKfzUAAiMACQpjJN8DAJwDACMACQpjJN8DAJwDAAAA.Moriwarrior:BAABNQAECn8dAAITAAgK5hpWSQANAQATAAgK5hpWSQANAQABNQAFFAUIDQAjADohAA==.',
Ms='Mspainsalot:BAAANQAECggIAQAAAA==.',
Mu='Murky:BAAANQAECggIEwAAAA==.Murnemerch:BAAANQADCgcIMQAAAA==.Musclewizard:BAABNQAECn8kAAITAAcKxhkcKQBjAQATAAcKxhkcKQBjAQAAAA==.',
My='Myrthael:BAAANQADCgUIBQAAAA==.Mythiks:BAAANQADCgIIAgABNQAECgoKIQALAJwNAA==.',
['Mï']='Mïlo:BAABNQAECn8YAAIPAAoKkw9YLAC4AQAPAAoKkw9YLAC4AQAAAA==.',
['Mô']='Môon:BAAANQAECgUIBQAAAA==.',
['Mø']='Mønsters:BAAANQAECgMIAwAAAA==.',
Na='Nancybrew:BAABNQAECn8hAAIPAAkKshrNGACAAgAPAAkKshrNGACAAgAAAA==.Natalie:BAAANQADCggICAABNQAECggICwAMAAAAAA==.',
Ne='Nesqwik:BAAANQADCggIIQAAAA==.Nevan:BAABNQAECn8oAAIFAAoK1x7IGAAWAwAFAAoK1x7IGAAWAwAAAA==.Neverender:BAAANQADCgMIAwABNQAECgcIEQAMAAAAAA==.',
Ni='Nidalee:BAAANQAECgcIDgAAAA==.Nineball:BAABNQAECn8rAAMYAAoKTxo1GQAVAQAZAAcKehgdQgDCAQAYAAcKNRo1GQAVAQAAAA==.Niyx:BAAANQAECgYIDgAAAA==.',
No='Noochallange:BAABNQAECn8lAAIZAAkK3h0SAwAfAgAZAAkK3h0SAwAfAgAAAA==.Norex:BAACNQAFFH8PAAMJAAYKHgyDBQDfAAAJAAUKewuDBQDfAAAKAAQKNwlNGQDVAAA1AAQKfyEABAkACgqGGHM1AAQCAAkACQqGGHM1AAQCABoABgqbDbqCABQBAAoAAwpOFAeXALAAAAAA.Notgood:BAAANQAECgMIBQAAAA==.',
Nu='Nuggie:BAABNQAECn8cAAMOAAgKLRFxIgBkAQAOAAgKLRFxIgBkAQAXAAEKWBB5cwA7AAAAAA==.',
Ny='Nylariaa:BAAANQADCgYIBgAAAA==.Nymia:BAAANQAECggIDwAAAA==.',
Ol='Oldmagic:BAAANQAECgQIEAAAAA==.Olzpot:BAAANQAECgEIAQAAAA==.',
Oo='Ooglaboogla:BAABNQAECn8rAAMQAAoK5BsJPwB5AgAQAAgK0B0JPwB5AgAIAAgKVRwacAC7AQAAAA==.',
Or='Orbitguy:BAAANQADCgUIBQAAAA==.Orbutt:BAAANQADCgYICgAAAA==.Orillian:BAAANQADCgYIBwAAAA==.',
Ov='Overtime:BAAANQAECgcIEQAAAA==.',
Ox='Oxyrotten:BAAANQAECgIJAgAAAA==.',
Pa='Palablort:BAABNQAECn8dAAMFAAkKSR4/LwCpAgAFAAkKSR4/LwCpAgAEAAUKdRVr9wAvAQAAAA==.Panzeria:BAABNQAECn8cAAIjAAkKfiN9DgAIAwAjAAkKfiN9DgAIAwAAAA==.Pawsome:BAABNQAECn8YAAInAAgKSxhEEgA+AgAnAAgKSxhEEgA+AgAAAA==.',
Pi='Pixel:BAAANQAECgMIBwAAAA==.',
Pl='Plinkie:BAAANQADCgEIAQAAAA==.',
Pm='Pmon:BAAANQADCgYIBgAAAA==.',
Pr='Predofdisney:BAAANQAECgIIAgAAAA==.Prlestest:BAAANQAECgYIEQABNQAECgkJQQAeAG8jAA==.Proowee:BAAANQAECggIDwAAAA==.Propayne:BAAANQAECggIBQAAAA==.',
Ps='Pseudoholy:BAAANQAECgUICQAAAA==.',
Pu='Pukebreath:BAAANQADCgEIAQAAAA==.Putridvigor:BAABNQAECn8sAAIKAAoKdiLgBAAFAgAKAAoKdiLgBAAFAgAAAA==.',
['Pä']='Pälii:BAABNQAECn8jAAIEAAkKEg97HQCsAQAEAAkKEg97HQCsAQAAAA==.',
Qi='Qizai:BAAANQAECgEIAQAAAA==.',
Ra='Ramaan:BAAANQAECgIIAgAAAA==.Rastaa:BAABNQAECn8hAAMLAAoKnA2xBgB9AQALAAoKnA2xBgB9AQASAAEKAABmXgE1AAAAAA==.Ravette:BAABNQAECn8fAAIdAAkK8x7EGQDNAgAdAAkK8x7EGQDNAgAAAA==.Ravissante:BAAANQAECgEIAQAAAA==.Ravyndrath:BAAANQADCgMIAwAAAA==.Rawranator:BAAANQAECgQIBgAAAA==.',
Re='Reesecupthis:BAAANQAECgEIAQABNQAFFAcIEgAGAJ4VAA==.',
Rh='Rhonis:BAAANQADCgEIAQAAAA==.',
Ri='Ricksancheez:BAABNQAECn8aAAMGAAoKqBLsLQBuAQAEAAcK+A//yQCIAQAGAAcKkBTsLQBuAQAAAA==.',
Ro='Roidgnome:BAAANQAECgEIBAAAAA==.Ronnycoleman:BAAANQADCgIIAgAAAA==.',
Ru='Runeka:BAAANQAECgEIAQABNQAECgkJJQAcAPEhAA==.',
Ry='Ryleth:BAAANQADCggIDQAAAA==.',
Sa='Safehaven:BAAANQAECgYIEAAAAA==.Samwìse:BAACNQAFFH8TAAIWAAUKuBKJBQCOAQAWAAUKuBKJBQCOAQA1AAQKf0cAAxYACgpnIgIUAC4DABYACgpnIgIUAC4DACMABgpTDadBACQBAAAA.Sarenrae:BAAANQAECgUICgABNQAECggIJwAUAL0bAA==.Sarranidan:BAABNQAECn8WAAISAAcK2xm/cQAuAgASAAcK2xm/cQAuAgABNQAECgkJNgADANQcAA==.Sathelyn:BAAANQADCgcIBwABNQAECgoKKwAbANIKAA==.Sato:BAAANQABCgIIAgAAAA==.',
Sc='Scatman:BAAANQADCgUIBQAAAA==.Scire:BAAANQAECgQIBAAAAA==.Scopenrage:BAAANQAECgQIBAABNQAECgoKGQAaAE8eAA==.',
Se='Sedontas:BAAANQAECgQIBQAAAA==.Senggolbacok:BAAANQAECgQICwAAAA==.Serengenuity:BAACNQAFFH8VAAMWAAYKPBegCAABAgAWAAYK8BagCAABAgAVAAMK0xDoAQDzAAA1AAQKfycABBYACgrBIQklANgCABYACgqYIQklANgCABUABgqhH2oHAAACACMABAp0ILtEABEBAAAA.Serenidin:BAAANQADCgYIBgAAAA==.',
Sh='Shampane:BAAANQADCgUIBQABNQAECgkJQQAeAG8jAA==.Shamwow:BAAANQAECgEIAQAAAA==.Shark:BAAANQAECgcIEQAAAA==.Sheera:BAAANQADCgEIAQAAAA==.Shiggles:BAAANQAECggIDAABNQAFFAUIDAAIAIwJAA==.Shiggyll:BAAANQAECgMIBAABNQAFFAQIDAAWALMcAA==.Shiryunuri:BAAANQADCgYIBgAAAA==.Shiv:BAAANQAECggIAQABNQAFFAYICwADALEQAA==.Shizzo:BAAANQADCgQIBAAAAA==.Shmoople:BAAANQADCgcIDAAAAA==.Shockin:BAABNQAECn8dAAIhAAkKWhAnFAAmAgAhAAkKWhAnFAAmAgAAAA==.Shootin:BAAANQAECgIJBAAAAA==.Shypoke:BAAANQABCgEIAQAAAA==.Shøstákovich:BAAANQAECgEIAQAAAA==.',
Si='Sifen:BAABNQAECn8gAAMFAAkKARZFVQAaAgAFAAkKARZFVQAaAgAEAAEKSQefyAEkAAABNQAFFAQIDQAQALEeAA==.Sifting:BAABNQAECn86AAIDAAoKAxz8BQByAgADAAoKAxz8BQByAgAAAA==.Sinsheretic:BAAANQAECgQIBAAAAA==.Sinswrath:BAACNQAFFH8VAAIEAAYKLCE4AwBKAgAEAAYKLCE4AwBKAgA1AAQKfygAAgQACgrHJVYaAFsDAAQACgrHJVYaAFsDAAAA.',
Sk='Skidxx:BAAANQADCgYIDQAAAA==.Skulker:BAAANQADCgMIBgAAAA==.Skygnome:BAACNQAFFH8IAAMHAAMK9gYzEgDAAAAHAAMK9gYzEgDAAAAkAAEKrwDsDQAuAAA1AAQKfyQAAwcACgpIGkQPALQCAAcACQrPGUQPALQCACQAAQp2C54OADIAAAAA.Skyhørn:BAAANQAECgIIAgAAAA==.',
Sl='Slaye:BAAANQAECgQICAAAAA==.Slimjjim:BAABNQAECn8YAAMIAAkKDBVhhwB4AQAIAAgKARNhhwB4AQAQAAYKexOWmgBjAQAAAA==.',
Sm='Smiteheal:BAAANQADCgYIBgAAAA==.Smores:BAAANQADCgEIAQABNQAFFAcIGQAUAH8iAA==.',
Sn='Snake:BAAANQADCgUIBQAAAA==.Sneakyteeth:BAABNQAECn83AAIYAAoKnBk7CQDhAgAYAAoKnBk7CQDhAgAAAA==.',
So='Songi:BAABNQAECn8vAAIaAAoKtCFuDwA7AwAaAAoKtCFuDwA7AwAAAA==.Soulstout:BAAANQADCgcIEAAAAA==.Soulwhisper:BAACNQAFFH8RAAIaAAYKIBY6BADuAQAaAAYKIBY6BADuAQA1AAQKfyoAAhoACgo1IlgYAPwCABoACgo1IlgYAPwCAAAA.',
Sp='Spanda:BAABNQAECn8dAAIRAAgKvRcSDwAAAgARAAgKvRcSDwAAAgAAAA==.Sparrkel:BAAANQAECgQIBQAAAA==.Splageras:BAAANQAECgEIAQAAAA==.Splagzhul:BAAANQAECgQICAAAAA==.Splendi:BAAANQAECgQIBAABNQAECggIHQARAL0XAA==.Sprogg:BAAANQAECgEIAQAAAA==.Spyropaly:BAABNQAECn8qAAIFAAkKaCGQDgBWAwAFAAkKaCGQDgBWAwAAAA==.Spyroshaman:BAAANQADCgUICQABNQAECgkJKgAFAGghAA==.',
St='Stampede:BAAANQADCggIDwAAAA==.Stepzlol:BAAANQADCgYIDwABNQADCgcIDQAMAAAAAA==.Stormsinger:BAABNQAECn8kAAMIAAkKgBYrSwA2AgAIAAkKgBYrSwA2AgAQAAgK7wsFeQC3AQAAAA==.',
Su='Sugarblast:BAACNQAFFH8OAAIQAAYKCxnTBgAOAgAQAAYKCxnTBgAOAgA1AAQKfzkAAxAACgptIP0LAIcDABAACgptIP0LAIcDACEABQr1HkUbALABAAAA.Sukaii:BAAANQAECgcIDgABNQAFFAQIDAAWALMcAA==.Summonuber:BAAANQAECgIIAQAAAA==.Suou:BAACNQAFFH8QAAMTAAYK3xaMEACyAQATAAUKfheMEACyAQAbAAEKAxWAAQBgAAA1AAQKfykAAxMACgrjH7hBAMUCABMACgrjH7hBAMUCABsAAQqcIFQsAFMAAAAA.',
Sv='Svekkê:BAAANQAECgcIAQAAAA==.',
Sy='Sylint:BAAANQADCgYICwAAAA==.Sylliseas:BAAANQADCgYIBgAAAA==.',
Ta='Tandaley:BAAANQADCgQIBQABNQAECgkJJAAIAIAWAA==.Tandea:BAAANQAECgYIBgAAAA==.Tanthyr:BAAANQADCgQIBQABNQAECgkJJAAIAIAWAA==.Targon:BAAANQADCgcIDQAAAA==.',
Te='Terallaa:BAAANQAECgUICAABNQAECgcIBwAMAAAAAA==.Testme:BAAANQADCggICwAAAA==.Textaco:BAAANQADCgEIAQAAAA==.',
Th='Thedevilssin:BAAANQAECgYICwAAAA==.Theodas:BAAANQAECgcIDQAAAA==.Thiccgnome:BAACNQAFFH8JAAIWAAQKtQ6zIADbAAAWAAQKtQ6zIADbAAA1AAQKfxYAAhYACQprGCw6AIACABYACQprGCw6AIACAAAA.Thiccthighs:BAAANQAECgEIAQAAAA==.Thirdlegolas:BAAANQAECgEIAQAAAA==.Thuuros:BAABNQAECn8zAAIaAAoKrhjnAwALAgAaAAoKrhjnAwALAgAAAA==.Thyrissuraux:BAAANQADCgIIAgAAAA==.',
Ti='Tikariia:BAAANQAECgQIBAAAAA==.Tiktok:BAAANQAECgUIBQAAAA==.Tipsygypsy:BAABNQAECn8YAAMeAAcKJxI+HgD7AAADAAYKCAowLQFBAQAeAAUKKhQ+HgD7AAAAAA==.Tirent:BAAANQAECgQICQAAAA==.',
To='Tokenbeef:BAAANQAECgcIEgAAAA==.Tokenshaman:BAABNQAECn8rAAIhAAkK+RLGEABeAgAhAAkK+RLGEABeAgAAAA==.Tokentrees:BAAANQADCgUJBQAAAA==.Touchspell:BAABNQAECn8oAAIDAAoK1Ah63ADPAQADAAoK1Ah63ADPAQAAAA==.Toxicdk:BAACNQAFFH8FAAQKAAMKdRlwLgA7AAAaAAEKZxwpHwBPAAAJAAEKAACvHQBIAAAKAAIKdRlwLgA7AAA1AAQKfyIABAkACgrhIPMuACsCAAkACQqFHvMuACsCAAoABwraHnRIANYBABoABArqI8tcAJwBAAAA.Toxicshamy:BAABNQAECn8WAAMQAAkKKRXASgBLAgAQAAkKKRXASgBLAgAIAAYK3hXWJQBMAQABNQAFFAMIBQAKAHUZAA==.',
Tr='Traylay:BAACNQAFFH8QAAIEAAYK6BHoCgCaAQAEAAYK6BHoCgCaAQA1AAQKfyAAAgQACgoPIidBANECAAQACgoPIidBANECAAAA.Trixaintime:BAAANQADCgcIBwAAAA==.Trommel:BAAANQAECgYICwAAAA==.Trydoom:BAAANQADCgYICQAAAA==.Trèè:BAAANQADCgMIBQAAAA==.',
Tt='Ttocs:BAACNQAFFH8NAAIQAAQKsR7YBAAIAQAQAAQKsR7YBAAIAQA1AAQKfzgAAhAACgphJHAEAMgDABAACgphJHAEAMgDAAAA.',
Tu='Tujori:BAACNQAFFH8VAAIWAAYKrQu4DADAAQAWAAYKrQu4DADAAQA1AAQKfycAAhYACgr/F+NHAE8CABYACgr/F+NHAE8CAAAA.',
Tw='Twherk:BAACNQAFFH8GAAIFAAQKPxdoEQBMAQAFAAQKPxdoEQBMAQA1AAQKfy8AAgUACgphHRgEALACAAUACgphHRgEALACAAE1AAUUBQgMAAgAjAkA.Twoeye:BAAANQADCgYIBgAAAA==.',
Ug='Uglydorf:BAABNQAECn8xAAMSAAoKNBYBEgDhAQASAAoKNBYBEgDhAQALAAEKwAOgmwAkAAAAAA==.',
Um='Umokthra:BAAANQAECgIIAgAAAA==.',
Us='Ustoo:BAABNQAECn8lAAMeAAcK8xVQDQDcAQAeAAcK8xVQDQDcAQADAAEKMwJR2gEoAAAAAA==.',
Va='Vae:BAAANQAECgMJAwAAAA==.Vaeros:BAABNQAECn8eAAIkAAcK8QsiDgBmAQAkAAcK8QsiDgBmAQAAAA==.Valanteil:BAAANQABCgYIBAABNQAECgkJJAAIAIAWAA==.Varcina:BAABNQAECn8hAAIOAAoK8hidLQDPAgAOAAoK8hidLQDPAgABNQAFFAUIDQAaALAeAA==.Variana:BAABNQAECn8lAAMcAAkK8SEcBAAOAwAcAAgK5iEcBAAOAwAdAAMKGhx2LwCuAAAAAA==.Vaylle:BAAANQADCgQJBAAAAA==.',
Ve='Vekz:BAABNQAECn8wAAIFAAoKUR1YBwBSAgAFAAoKUR1YBwBSAgAAAA==.Veledrokos:BAAANQADCgEIAQAAAA==.Veles:BAAANQAECgEIAQAAAA==.Velicia:BAAANQAECgMIBQAAAA==.Velytia:BAAANQAECgcIEQAAAA==.Verytight:BAAANQAECgYICAAAAA==.Vexøs:BAAANQADCggIDwAAAA==.',
Vi='Vitiliga:BAABNQAECn8eAAIbAAgKDAeUFwAmAQAbAAgKDAeUFwAmAQAAAA==.',
Vo='Volcanicbird:BAAANQAECgUICAAAAA==.Vomax:BAAANQADCgEIAQAAAA==.',
Wa='Wasteofpants:BAAANQAECgUIBwAAAA==.Waterbôy:BAAANQAECgYIDwABNQAFFAUIDQAFAIcbAA==.',
Wh='Whoasked:BAAANQADCgMIAwABNQAFFAUIDAADANscAA==.Whîrly:BAAANQADCgUIBgAAAA==.',
Wo='Wolf:BAAANQAECgIIAgAAAA==.',
Wt='Wtfheal:BAAANQAECggIEwABNQAFFAUIDAAIAIwJAA==.',
Wu='Wumbology:BAAANQAECgYIBgAAAA==.',
['Wà']='Wàrrior:BAAANQADCgUICQAAAA==.',
Ya='Yakimandu:BAAANQADCggICAABNQAECgoKJAAIACYfAA==.Yamashaman:BAABNQAECn8kAAIIAAoKJh9EJADVAgAIAAoKJh9EJADVAgAAAA==.Yamo:BAAANQADCggIHAAAAA==.Yardgnome:BAABNQAECn8jAAMUAAkKcR2UBQABAgAUAAgKNh2UBQABAgABAAcKAxIVTQCtAQAAAA==.',
Yu='Yuna:BAABNQAECn8kAAIWAAcKQB2vFgC8AQAWAAcKQB2vFgC8AQAAAA==.',
Za='Zacheris:BAABNQAECn8WAAIDAAgKpBvHkQBcAgADAAgKpBvHkQBcAgAAAA==.Zafod:BAAANQAECgIIAgAAAA==.Zalvator:BAAANQABCggIEgABNQAECggICwAMAAAAAA==.Zamasu:BAAANQAECgIJAwAAAA==.Zapped:BAAANQAECgQIBQAAAA==.Zaszadin:BAECNQAFFH8IAAIEAAQKQRheBgD4AAAEAAQKQRheBgD4AAA1AAQKfx0AAgQACQotHWhbAIYCAAQACQotHWhbAIYCAAAA.Zaszhadoom:BAEANQADCgYIBgABNQAFFAQICAAEAEEYAA==.',
Ze='Zeltron:BAAANQADCgUICgAAAA==.Zerax:BAABNQAECn8pAAIHAAoKPBTRAQBVAgAHAAoKPBTRAQBVAgAAAA==.Zerolinkin:BAAANQAECgEIAQAAAA==.',
Zi='Zillagoth:BAAANQADCggICQAAAA==.Zira:BAABNQAECn8jAAImAAgKthMJHADDAQAmAAgKthMJHADDAQAAAA==.',
Zo='Zombidruid:BAAANQAECgMIBAAAAA==.Zombiebubble:BAAANQAECgcICgAAAA==.Zoìdberg:BAACNQAFFH8HAAIIAAIKRRAwIwCAAAAIAAIKRRAwIwCAAAA1AAQKfyMAAggACgrYHTAhAOQCAAgACgrYHTAhAOQCAAAA.',
Zs='Zselk:BAAANQADCgUIBQAAAA==.Zshot:BAAANQAECgcIDwAAAA==.',
Zu='Zubzer:BAAANQADCgYIBgAAAA==.',
Zy='Zythane:BAAANQADCggICAAAAA==.',
Zz='Zzor:BAACNQAFFH8RAAIDAAUKghp8BgA8AQADAAUKghp8BgA8AQA1AAQKfzgAAgMACgqnIdUiAFEDAAMACgqnIdUiAFEDAAAA.',
['Är']='Ärtemìs:BAAANQADCgQIBAAAAA==.',
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

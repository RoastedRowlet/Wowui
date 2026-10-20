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

local lookup = {'Shaman-Restoration','Druid-Restoration','Paladin-Retribution','Paladin-Holy','Hunter-BeastMastery','DeathKnight-Unholy','DeathKnight-Frost','Druid-Balance','Rogue-Assassination','Rogue-Subtlety','DeathKnight-Blood','Warrior-Arms','Shaman-Enhancement','Monk-Windwalker','Shaman-Elemental','Warlock-Demonology','DemonHunter-Devourer','Warrior-Fury','Unknown-Unknown','Warlock-Destruction','Paladin-Protection','Priest-Shadow','Priest-Holy','Priest-Discipline','Hunter-Marksmanship','Evoker-Preservation','Evoker-Devastation','Warlock-Affliction','Evoker-Augmentation','Monk-Brewmaster','Druid-Feral','Mage-Arcane','Mage-Frost','Monk-Mistweaver','Warrior-Protection','Hunter-Survival','DemonHunter-Havoc','DemonHunter-Vengeance','Mage-Fire',}
local provider = {region='US',realm="Mug'thol",name='US',type='weekly',zone=53,date='2026-10-20',data={Ad='Adjust:BAABNQAECn8XAAIBAAgKHh4rQQBcAgABAAgKHh4rQQBcAgABNQAFFAcIGQACAGkZAA==.Admirlakbar:BAAANQADCgIIAgAAAA==.',
Ae='Aedrenis:BAAANQADCgUIDgAAAA==.Aegrisomnia:BAAANQABCgMIAwABNQAECgoKMAABALIeAA==.Aejra:BAAANQAECgQIBAABNQAECgoKMAABALIeAA==.Aenstus:BAAANQADCgMJAwAAAA==.Aeropunk:BAAANQADCgIJAgAAAA==.Aerys:BAABNQAECn8YAAMDAAgKiQkGIgHmAAADAAUKxAgGIgHmAAAEAAUKVAUizADjAAAAAA==.Aerøs:BAABNQAECn8UAAIFAAgKew7zgQAIAgAFAAgKew7zgQAIAgAAAA==.',
Ag='Aggiz:BAAANQAECgYIDgABNQAECgoKMAAFADseAA==.',
Aj='Ajaxprime:BAABNQAECn8oAAMGAAkKmyWUFwAAAwAGAAkKmyWUFwAAAwAHAAEK6whesQAvAAAAAA==.',
Ak='Akiojonës:BAAANQADCgYIBgAAAA==.',
Al='Alfabika:BAAANQAECgYICAAAAA==.Alzim:BAABNQAECn8WAAIIAAgKnhyeNwAwAgAIAAgKnhyeNwAwAgAAAA==.',
Am='Amoriara:BAAANQADCgUIFgAAAA==.',
An='Angry:BAAANQAECgYIDQAAAA==.Ankelbiter:BAABNQAECn8cAAMJAAkK5hyjGgCoAgAJAAgK3B6jGgCoAgAKAAIKIBFeRQCNAAAAAA==.Anûbis:BAABNQAECn8eAAILAAgKWws7FwAuAQALAAgKWws7FwAuAQAAAA==.',
Ar='Aragos:BAAANQAECgYIDAAAAA==.Arazarion:BAAANQAECgQIBAAAAA==.Arcelon:BAAANQAECgEIAgAAAA==.Arwenatak:BAABNQAECn8yAAMDAAoK+x7PDwD9AQADAAoK+x7PDwD9AQAEAAQK/w2qzADiAAAAAA==.',
As='Asgardian:BAAANQAECgMICAAAAA==.Asmoon:BAACNQAFFH8YAAMIAAcK+BgIAgCtAQAIAAcK+BgIAgCtAQACAAEKYgVIDAA9AAA1AAQKfxkAAwgACQqqFNw+AAMCAAgACAqAFdw+AAMCAAIAAwrdFQcfANMAAAAA.',
At='Athren:BAABNQAECn8bAAIDAAgK8BwRcABPAgADAAgK8BwRcABPAgAAAA==.Athrogate:BAABNQAECn8rAAIMAAgKLxhKHgCLAQAMAAgKLxhKHgCLAQAAAA==.',
Au='Auraloxious:BAAANQAECgMIAwAAAA==.',
Az='Azmun:BAAANQAECgQIBAABNQAFFAcIGAAIAPgYAA==.Azmunn:BAAANQAECgQIBgABNQAFFAcIGAAIAPgYAA==.',
Ba='Baelzadru:BAAANQAECgUICwAAAA==.Baelzheron:BAAANQAECgUICwAAAA==.Baksylyk:BAAANQAECgMIBAABNQAECgoKIgADACIgAA==.Balgart:BAAANQAECgMIAwAAAA==.Ballador:BAAANQAECggIDAAAAA==.Barakas:BAAANQADCgUICAAAAA==.Barakoshamma:BAABNQAECn83AAINAAkKbiQyAQC0AwANAAkKbiQyAQC0AwAAAA==.Barazudar:BAABNQAECn8mAAIEAAgKihM/YgDxAQAEAAgKihM/YgDxAQAAAA==.Baroke:BAAANQADCgYIBgAAAA==.Barragadin:BAAANQADCgUIBQABNQAECggIGAAOAEIWAA==.Barrageobama:BAAANQADCgUIBQAAAA==.Barreta:BAABNQAECn8iAAIFAAoKiQ0jGgCwAQAFAAoKiQ0jGgCwAQAAAA==.',
Be='Beardsize:BAAANQAECgIIAgABNQAFFAcIGQACAGkZAA==.Beck:BAABNQAECn8sAAMPAAkKzQQl1wDmAAAPAAcKAgMl1wDmAAABAAkK9AT2UAC8AAAAAA==.Beefykin:BAAANQAECgYIDwAAAA==.Bellamuerté:BAAANQAECgQIBAABNQAECgoKJQAQAPoVAA==.Bellámuerté:BAABNQAECn8lAAIQAAoK+hXfTgBoAgAQAAoK+hXfTgBoAgAAAA==.Bemmy:BAAANQAECgQIDAABNQAECgoKMAABALIeAA==.',
Bi='Bigdrandyy:BAABNQAECn8WAAMBAAYKsiE7TQAvAgABAAYKsiE7TQAvAgAPAAUKfQmIxwADAQAAAA==.Biggspal:BAAANQADCgYIBgAAAA==.',
Bl='Blackbird:BAABNQAECn8vAAIRAAoK1h45AgBDAgARAAoK1h45AgBDAgAAAA==.Blackmage:BAAANQADCgYIBgAAAA==.Bloodlordzz:BAABNQAECn8aAAIDAAcKEQ2+zwB8AQADAAcKEQ2+zwB8AQAAAA==.Bloodreina:BAABNQAECn8VAAMSAAcK0BzHDgDBAQASAAUKPSPHDgDBAQAMAAIKLBODMQFxAAABNQAECggIEgATAAAAAA==.Blutkind:BAAANQAECggICwAAAA==.',
Bo='Bob:BAABNQAECn8YAAMUAAcKDxWFCQCGAAAQAAUKWBRoWADRAAAUAAIKfRaFCQCGAAAAAA==.Bobtheknob:BAAANQAECgUIBQAAAA==.Bockandcalls:BAAANQAECgYICgAAAA==.Bolbi:BAAANQAECgIIAwAAAA==.Bootyhunting:BAABNQAFFH8JAAIFAAUKCg69CQDLAAAFAAUKCg69CQDLAAAAAA==.',
Br='Brahm:BAAANQAECgUICwABNQAECgoKLgAPAGIbAA==.Brdua:BAAANQADCgYIBgAAAA==.Breadnbudda:BAAANQADCgcIHAAAAA==.Brideofloco:BAAANQABCgEIAQAAAA==.Brogar:BAAANQADCgcIHwAAAA==.',
Bu='Bubblekush:BAABNQAECn8bAAIVAAkKExXsCABsAQAVAAkKExXsCABsAQABNQAFFAcIEwAWAH4VAA==.Buffknight:BAAANQAECgQICQABNQAECgoKLgAPAGIbAA==.Bulkam:BAAANQAECgYIEAAAAA==.Bulkazarr:BAABNQAECn8hAAIBAAoKqhl7PgBmAgABAAoKqhl7PgBmAgAAAA==.Burbuja:BAAANQADCggICAABNQAECgkJLQAXAEAkAA==.',
['Bí']='Bíssell:BAABNQAECn8XAAIMAAkKEBj8CQAdAgAMAAkKEBj8CQAdAgAAAA==.',
['Bù']='Bùllrùsh:BAAANQABCgEIAQAAAA==.',
Ca='Callabash:BAABNQAECn85AAMBAAoKkxvuEgC+AQABAAoKkxvuEgC+AQAPAAYKAQi7uQAfAQAAAA==.Catnapped:BAAANQAFFAEIAQABNQAFFAIIBgAEAMEQAA==.',
Ce='Celarena:BAABNQAECn8YAAIUAAcKywLwLwAJAQAUAAcKywLwLwAJAQAAAA==.Cermit:BAAANQAECgEIAQAAAA==.',
Ch='Cheefkdavi:BAAANQAECgUICQABNQAECgoKHgALAKAhAA==.Chewie:BAAANQADCgUIBQAAAA==.Chilla:BAAANQADCgQIBAAAAA==.Chomrogg:BAAANQAECgYJBwAAAA==.Chopzzpala:BAAANQADCgYICAAAAA==.Choubelle:BAAANQADCgQIBAAAAA==.Chuuck:BAEANQABCgQIBAAAAA==.Chyp:BAABNQAECn8kAAMDAAgKtRnmdQBBAgADAAgKtRnmdQBBAgAVAAQKsRd0OAAoAQAAAA==.Chzlagoo:BAACNQAFFH8XAAIPAAgKyhv1AADhAgAPAAgKyhv1AADhAgA1AAQKfyUAAw8ACgrXI6IJAJoDAA8ACQp/JaIJAJoDAA0AAQpCGCkeAEsAAAAA.Chzpriest:BAACNQAFFH8PAAIWAAgK7ROiAgBeAgAWAAgK7ROiAgBeAgA1AAQKfzMABBYACQp8IpMMACADABYACQp8IpMMACADABcACAquFNFXABsCABgAAQryClorAC4AAAE1AAUUCAgXAA8AyhsA.',
Ci='Cichorì:BAACNQAFFH8RAAMQAAQKERksGQArAQAQAAMKrCMsGQArAQAUAAIKMhFZDwCWAAA1AAQKfysAAxQACgpRI1sHAJACABAACAo6JNUwAMQCABQACQr1G1sHAJACAAAA.Cipa:BAAANQADCgcIBwAAAA==.Circee:BAAANQAECgUICAAAAA==.',
Co='Colmer:BAAANQADCgMIAwAAAA==.',
Cp='Cptvoker:BAAANQADCgIIAgAAAA==.',
Cr='Creckko:BAAANQADCgQIBgAAAA==.Crockito:BAACNQAFFH8uAAIPAAoK4CEPAAD/AgAPAAoK4CEPAAD/AgA1AAQKfyQAAw8ACgr5Ju4AAPoDAA8ACgr5Ju4AAPoDAAEAAQpXDogkASgAAAAA.',
Cy='Cyrusdavirus:BAAANQADCgUIBQAAAA==.',
Da='Dabu:BAAANQAECgQIBAAAAA==.Dama:BAAANQADCgIIAgABNQADCgIIAgATAAAAAA==.Danto:BAABNQAECn8gAAIJAAoKEB6xBwCgAQAJAAoKEB6xBwCgAQABNQAECgoKLgAPAGIbAA==.Dantos:BAAANQAECgUICgABNQAECgoKLgAPAGIbAA==.Darc:BAAANQAECgUICAABNQAECgYIDAATAAAAAA==.Darktroll:BAABNQAECn8zAAIFAAoKZxTPUAB9AgAFAAoKZxTPUAB9AgAAAA==.',
De='Deemo:BAAANQADCgQIBwABNQADCggIFwATAAAAAA==.Deladore:BAAANQADCgYIBgAAAA==.Depoprovera:BAABNQAECn8rAAIVAAoKDxISHwDuAQAVAAoKDxISHwDuAQAAAA==.Deqz:BAABNQAECn8qAAMFAAoKTB22KQB0AQAZAAgKtBiwHgBbAgAFAAUK3By2KQB0AQAAAA==.',
Dh='Dhanto:BAAANQAECgQIBQABNQAECgoKLgAPAGIbAA==.',
Di='Diezel:BAAANQAECgIIAgABNQAECggIDwATAAAAAA==.Dilox:BAAANQAECgUICAAAAA==.Dinosaur:BAABNQAECn8qAAMaAAgKZBq4GQAmAgAaAAgKZBq4GQAmAgAbAAcK0hjPEwASAgABNQAFFAUIDAAEAN8QAA==.Dirtydee:BAABNQAECn8yAAILAAoK6AtkFwAtAQALAAoK6AtkFwAtAQAAAA==.Dirtydrood:BAAANQABCgIIAgAAAA==.Disaaya:BAABNQAECn8lAAIFAAgKJg6iLgBlAQAFAAgKJg6iLgBlAQAAAA==.Divinecheeks:BAAANQAECgIIBgAAAA==.',
Dj='Djangó:BAAANQAECgQIBwAAAA==.',
Do='Donto:BAAANQAECgUICQABNQAECgoKLgAPAGIbAA==.Dontos:BAAANQAECgUIDAABNQAECgoKLgAPAGIbAA==.Doodlebug:BAACNQAFFH8YAAILAAYKARtaAwBIAQALAAYKARtaAwBIAQA1AAQKfzIAAgsACgqQHr8LAIwBAAsACgqQHr8LAIwBAAAA.Dooshrocket:BAAANQAECgUIDAAAAA==.Dotsntaxes:BAACNQAFFH8QAAQUAAUKEQ9FFABpAAAQAAQK5RODJwDKAAAUAAIK3gJFFABpAAAcAAEKAABcFAAoAAA1AAQKfyYABBQACgqsGmYmAEIBABAACQqKF79sABgCABQABQrHEmYmAEIBABwAAQqNFZgoAEkAAAAA.',
Dr='Dracom:BAAANQAECgIIAwAAAA==.Dracuujin:BAAANQADCggICAABNQAFFAcIIgAXAKYgAA==.Dralioli:BAABNQAECn8jAAIEAAgK6BILFACzAQAEAAgK6BILFACzAQAAAA==.Dreadloccs:BAAANQAECgQIBwAAAA==.Dreanil:BAABNQAECn8hAAIBAAoKuhAtbADHAQABAAoKuhAtbADHAQAAAA==.Droho:BAABNQAECn8qAAMbAAkKmiMJBQBFAwAbAAkK+yAJBQBFAwAdAAMKPw5uCACNAAABNQAFFAcIGAAPAJgZAA==.Drroog:BAAANQADCgQIBQABNQAECgEIAQATAAAAAA==.',
Du='Dumper:BAAANQAECgIIAgAAAA==.',
Dw='Dwarfsize:BAAANQADCggICAABNQAFFAcIGQACAGkZAA==.',
Dz='Dzievana:BAAANQAECgEIAQAAAA==.',
['Dâ']='Dârn:BAABNQAECn8rAAQQAAoKCh2BKgDaAgAQAAkKfB2BKgDaAgAUAAEKASDUDgBeAAAcAAEK8BnaDgBSAAAAAA==.',
El='Eleweaver:BAAANQADCgcIDAAAAA==.Elissra:BAAANQADCgEIAQABNQAECgoKHAAWABcRAA==.Elvispræstly:BAAANQADCgYIBgAAAA==.',
En='Endfist:BAAANQAECggICQAAAA==.Enoughtalk:BAAANQAECgYIDAAAAA==.',
Eo='Eostre:BAABNQAECn8tAAQXAAkKQCR5BwCJAwAXAAkK8CN5BwCJAwAYAAMKfR7KEQAKAQAWAAEKSReAcQBEAAAAAA==.',
Es='Essa:BAAANQAECgIIAgAAAA==.',
Et='Ethernal:BAAANQAECgYIBgAAAA==.',
Eu='Eupherine:BAABNQAECn8wAAIXAAkK0CIPBADmAgAXAAkK0CIPBADmAgAAAA==.',
Ev='Evillarry:BAAANQADCgYIDAAAAA==.Evilpaladin:BAABNQAECn81AAIVAAoKnRkQDQDKAgAVAAoKnRkQDQDKAgAAAA==.Evilrico:BAAANQAECgEIAQAAAA==.',
Ez='Ezluz:BAABNQAECn8fAAMLAAkKNhoOFwAvAQALAAkKNhoOFwAvAQAGAAIKeBLQugB3AAAAAA==.',
Fa='Facsimile:BAABNQAECn8yAAIWAAkKCRXzAwDMAQAWAAkKCRXzAwDMAQAAAA==.',
Fe='Festers:BAABNQAECn8cAAMJAAkKaxf9KwA4AgAJAAgKSxj9KwA4AgAKAAQK2RB8NQANAQAAAA==.',
Fi='Fingerwalk:BAABNQAECn80AAMeAAkKAA8+AwB7AQAeAAkKyA4+AwB7AQAOAAIK+RE1JACPAAAAAA==.',
Fl='Flappi:BAABNQAECn8oAAIWAAkK2x3/DQAOAwAWAAkK2x3/DQAOAwAAAA==.Flappii:BAAANQADCgEIAQAAAA==.Flaster:BAAANQADCgYIBgAAAA==.Fluffykat:BAABNQAECn8vAAIIAAkK2Rj2BAD/AQAIAAkK2Rj2BAD/AQAAAA==.',
Fo='Fosho:BAACNQAFFH8YAAIPAAcKmBlDAgCYAgAPAAcKmBlDAgCYAgA1AAQKfyYAAg8ACgrkJGkEAMkDAA8ACgrkJGkEAMkDAAAA.',
Fr='Franch:BAABNQAECn8UAAILAAcKayHdKAB6AgALAAcKayHdKAB6AgAAAA==.Frank:BAAANQAECgEIAQABNQAECgkJFgAfABQZAA==.Fraud:BAAANQAECgcIDgABNQAECggIEgATAAAAAA==.Freelvlsvnty:BAAANQADCgYIBwAAAA==.Froddy:BAABNQAECn8XAAQPAAkKARg2XQAKAgAPAAcKvhk2XQAKAgANAAIKFRP+MQBWAAABAAEKFg+jkAA8AAAAAA==.Frostybox:BAAANQAECgQIBgAAAA==.Frylockk:BAABNQAECn8wAAQcAAoK3CG7AACLAwAcAAoK3CG7AACLAwAQAAYKVRoQmwCjAQAUAAEKQB1rawBKAAAAAA==.',
Fu='Furrykane:BAEBNQAECn8iAAQIAAkKuRg1OAAsAgAIAAkKfRc1OAAsAgACAAIK0w8+ZgBsAAAfAAEKyRcJPABJAAAAAA==.Future:BAABNQAECn81AAINAAgKzxUxBQCtAQANAAgKzxUxBQCtAQAAAA==.',
Ga='Gaara:BAABNQAECn8dAAIgAAgK6At0KwBuAQAgAAgK6At0KwBuAQAAAA==.Gamepunisher:BAABNQAECn8wAAMgAAoKKx1MBgBsAgAgAAoK1xtMBgBsAgAhAAcK6B70DADmAQAAAA==.Gares:BAAANQAECggIDgAAAA==.',
Gi='Giorbs:BAAANQADCgYIBgAAAA==.',
Go='Goatgeek:BAAANQABCgUIBgABNQAECgMIAwATAAAAAA==.Goham:BAABNQAECn8wAAIBAAoKsh54GAARAwABAAoKsh54GAARAwAAAA==.Goobe:BAAANQAECgQIBAABNQAECgoKMAAFADseAA==.Goontotem:BAAANQAECgEIAQABNQAECgUIBgATAAAAAA==.Gorro:BAAANQADCgYIBgAAAA==.',
Gr='Grimkai:BAAANQABCgMIAwAAAA==.Grogon:BAABNQAECn8XAAIFAAcKTA0WJQCFAQAFAAcKTA0WJQCFAQAAAA==.Gromlo:BAABNQAECn8nAAMCAAoKRCDDDgDnAgACAAoKRCDDDgDnAgAIAAIKSRaGmAB3AAAAAA==.Grulog:BAAANQAECgQICwAAAA==.',
Gu='Guldav:BAAANQADCgMIAwAAAA==.Gunny:BAABNQAECn8tAAMFAAoKsyLzDgD5AQAFAAoKsyLzDgD5AQAZAAIK5hdlcgBsAAAAAA==.',
['Gã']='Gã:BAAANQADCgUIBQAAAA==.',
['Gö']='Göld:BAAANQAECgUIBQAAAA==.',
Ha='Haeliman:BAAANQAECgIIAgAAAA==.Haileigh:BAAANQAECgMIDAAAAA==.Harleigh:BAAANQAECgQIBAAAAA==.Havöc:BAABNQAECn8jAAIMAAkKfRrqcgA8AgAMAAkKfRrqcgA8AgAAAA==.',
He='Herpenderper:BAAANQAECgQIBwAAAA==.',
Hi='Hikawa:BAABNQAECn82AAIgAAoKqiNGHwBcAwAgAAoKqiNGHwBcAwAAAA==.Hippocratic:BAABNQAECn8cAAMPAAoKSBpwVQAkAgAPAAgKFRpwVQAkAgABAAkKHRVOWgABAgAAAA==.',
Ho='Homunculous:BAAANQAECgIIAgAAAA==.Honortheox:BAAANQADCgEIAQABNQAECgMIAwATAAAAAA==.',
Hu='Huntemall:BAABNQAECn8jAAIFAAkKBRAnFgDFAQAFAAkKBRAnFgDFAQAAAA==.',
Hy='Hysteriix:BAEBNQAECn84AAIiAAkKViVrAQC8AwAiAAkKViVrAQC8AwAAAA==.',
Ic='Iceborn:BAAANQAECggIAwABNQAECggICQATAAAAAA==.Iceshards:BAABNQAECn8xAAIhAAkKXw2kBABiAQAhAAkKXw2kBABiAQAAAA==.Icraptotems:BAAANQAECgEIAQAAAA==.',
Id='Idtrapthat:BAAANQAECgYIDAAAAA==.',
Il='Illidankior:BAACNQAFFH8PAAIjAAUKoRsCAwBKAQAjAAUKoRsCAwBKAQA1AAQKfyYAAyMACgoxHFkIAM0CACMACgoxHFkIAM0CAAwAAQrIHS6oAFsAAAAA.Illidankmage:BAAANQAECgEIAQABNQAFFAUIDwAjAKEbAA==.Illirothas:BAAANQAECgUIBQABNQAECgoKLwAFAPwXAA==.',
Im='Imen:BAABNQAECn8eAAMCAAoKWR6aEQDFAgACAAoKWR6aEQDFAgAIAAMK4Ap5PgBnAAAAAA==.Impoosh:BAAANQAECgMIAwABNQAECgcIDAATAAAAAA==.Imsassy:BAAANQAECgUIDgAAAA==.',
In='Infect:BAAANQADCgIIAgABNQAECgYICAATAAAAAA==.Infectedbøb:BAAANQAECgQICgAAAA==.Inmortuae:BAAANQAECgQIBAABNQAECgoKLwAFAPwXAA==.Instågram:BAAANQAECgMIBQAAAA==.',
Io='Iornbane:BAABNQAECn8YAAIDAAcKRgzuyQCIAQADAAcKRgzuyQCIAQAAAA==.',
Ir='Irissela:BAAANQAECgYICwAAAA==.',
Is='Ispitmagic:BAAANQAECgYIBwAAAA==.',
Iv='Ivalice:BAABNQAECn8bAAQFAAkKyRawegAZAgAFAAcKeBmwegAZAgAZAAUK2Ag1UgDgAAAkAAIKAACTDwCRAAAAAA==.',
Iz='Izüal:BAAANQADCgYICQABNQAECgoKIgADACIgAA==.',
Ja='Jafbe:BAABNQAECn8dAAMEAAkKwh5CKgC+AgAEAAgKKR5CKgC+AgADAAIKwgpXkwFBAAAAAA==.Jaghatai:BAAANQAECgUICAAAAA==.Jammer:BAAANQADCgYIBgAAAA==.',
Ji='Jigsaw:BAAANQAECgMIBAAAAA==.Jimcarrey:BAAANQAECgQICwABNQAECgoKJwAFABwLAA==.Jimmyc:BAABNQAECn8SAAIFAAcKORW0TAAZAQAFAAcKORW0TAAZAQABNQAECgoKJwAFABwLAA==.Jimmyque:BAABNQAECn8nAAIFAAoKHAsfdwAhAgAFAAoKHAsfdwAhAgAAAA==.',
Jo='Joemauma:BAABNQAECn8rAAIhAAkKfxOjAgCwAQAhAAkKfxOjAgCwAQAAAA==.',
Jp='Jpam:BAACNQAFFH8OAAMhAAUKOxoTAwCVAAAgAAMKaSQ5PgDDAAAhAAIKIxUTAwCVAAA1AAQKfyYAAiAACgqgGhl7AIgCACAACgqgGhl7AIgCAAAA.',
Ju='Judges:BAAANQAECggIEAAAAA==.Jumbosize:BAACNQAFFH8ZAAICAAcKaRn3AQBVAgACAAcKaRn3AQBVAgA1AAQKfzEAAgIACgpXJH0BAL8DAAIACgpXJH0BAL8DAAAA.Jupîter:BAAANQAECgEIAQABNQAECgEIAgATAAAAAA==.Justamuslim:BAAANQADCggICAABNQAECgYICgATAAAAAA==.',
['Jä']='Jäde:BAAANQADCgMIAgAAAA==.',
Ka='Kaerlif:BAAANQAECgcIEgABNQAFFAYIEAAlAPkWAA==.Kaiyley:BAAANQAECgcIDAAAAA==.Kalastrian:BAABNQAECn8nAAIRAAkKPSOcAQB/AgARAAkKPSOcAQB/AgAAAA==.Kaliyah:BAAANQABCgQIBAAAAA==.Karatepally:BAAANQAECgIIAQAAAA==.Karateshock:BAABNQAECn8vAAMBAAkKNhzFAwDPAgABAAkKNhzFAwDPAgAPAAEKmgXSPAEvAAAAAA==.Kargo:BAAANQAECgYICwAAAA==.Karlmarks:BAAANQABCggIDgAAAA==.Kazuren:BAABNQAECn8pAAIbAAkKEgoHGQC4AQAbAAkKEgoHGQC4AQAAAA==.',
Ke='Keano:BAABNQAECn8iAAMEAAcKZxBnnABOAQAEAAYKhA1nnABOAQADAAQKSxkRDwEGAQAAAA==.Keeldemall:BAAANQAECgYIDAAAAA==.Kelia:BAAANQAECgUIBgABNQAECgoKLwAFAPwXAA==.Kelinna:BAABNQAECn8aAAIDAAkKhQ0hsAC/AQADAAkKhQ0hsAC/AQAAAA==.',
Kh='Khmelnitsky:BAAANQADCggICAAAAA==.',
Ki='Kilron:BAAANQABCgMIAgAAAA==.Kirin:BAABNQAECn8fAAIPAAcK3RsUTABGAgAPAAcK3RsUTABGAgAAAA==.Kitri:BAAANQADCgUIBwAAAA==.',
Kl='Klaye:BAABNQAECn8ZAAMMAAkK0g9GlwDiAQAMAAgKYhFGlwDiAQAjAAYKzAqmFACOAAABNQAECgoKLgAPAGIbAA==.',
Kn='Knatknom:BAAANQAECgIIAgAAAA==.',
Ko='Kodabonk:BAABNQAECn8tAAIeAAoKYx0EAgC9AQAeAAoKYx0EAgC9AQAAAA==.Kodanorth:BAAANQAECgEJAQABNQAECgoKLQAeAGMdAA==.Korthos:BAABNQAECn8UAAImAAcK3xtmDAAAAgAmAAcK3xtmDAAAAgAAAA==.Kotara:BAAANQADCggIDwAAAA==.',
Kr='Kraur:BAABNQAECn8vAAIFAAoK/Be1PAC0AgAFAAoK/Be1PAC0AgAAAA==.Krizzel:BAAANQADCgYIBgABNQAECgQIBwATAAAAAA==.',
['Kì']='Kìngpin:BAABNQAECn8rAAIFAAoK2BnCQwCgAgAFAAoK2BnCQwCgAgAAAA==.',
La='Laarry:BAAANQADCgUIBQABNQAFFAIIBgAEAMEQAA==.Lam:BAAANQADCgEIAQAAAA==.Lammp:BAACNQAFFH8HAAMPAAQKDQjaBwDWAAAPAAQKDQjaBwDWAAABAAEK/As1KQBUAAA1AAQKfyUAAwEACgpmG+YwAJ4CAAEACQqnG+YwAJ4CAA8ACArSFPZcAAsCAAAA.Lamppally:BAAANQAECgMIAwABNQAFFAQIBwAPAA0IAA==.Lampshade:BAAANQADCggICAABNQAFFAQIBwAPAA0IAA==.Laws:BAABNQAECn81AAIHAAkK6RQOMAAlAgAHAAkK6RQOMAAlAgAAAA==.Lazydragon:BAABNQAECn8mAAQdAAoKqQo2DwBNAQAbAAkKVgZjIABRAQAdAAcKJQ02DwBNAQAaAAcKyAnEBwBKAQAAAA==.',
Li='Liaeda:BAABNQAECn84AAMkAAoKdAuhAQCyAQAkAAoKdAuhAQCyAQAFAAQK2gmTEQHiAAAAAA==.Lianshi:BAAANQADCgUIBQAAAA==.Linainverse:BAAANQAECgUIDAAAAA==.Lingbane:BAAANQAECgEIAQABNQAECgoKMAAcANwhAA==.Litchslapped:BAAANQADCgcIBwAAAA==.Lixie:BAAANQADCggICAAAAA==.',
Lo='Lolo:BAAANQADCggICAABNQAFFAcIGAAPAJgZAA==.Loosie:BAAANQADCgEIAQAAAA==.Lost:BAAANQADCgUIBQABNQAECgkJNQAHAOkUAA==.Lovely:BAAANQAECgUIDAAAAA==.',
Lu='Luduhcris:BAAANQADCgYIEAAAAA==.Lugnuts:BAAANQAECgUIDAAAAA==.Lumiltiand:BAABNQAECn8jAAMGAAoKqCDlHADeAgAGAAkKHiPlHADeAgAHAAIKFBaiQQCeAAABNQAFFAIIAwATAAAAAA==.',
Lw='Lwaxana:BAAANQAECgQIBgAAAA==.',
Ma='Maceon:BAAANQADCgcIBwAAAA==.Makloy:BAAANQAECgEIAQAAAA==.Makuahwe:BAAANQADCggICAAAAA==.Malgoros:BAAANQAECgQIBAABNQAECgkJMgAWAAkVAA==.Malgrendin:BAABNQAECn8rAAIFAAoK+SOcBwCgAwAFAAoK+SOcBwCgAwAAAA==.Malty:BAABNQAECn8aAAIMAAgKSxvecgA8AgAMAAgKSxvecgA8AgAAAA==.Malédictias:BAAANQAECgQICQAAAA==.Manataurus:BAAANQADCgYIBgAAAA==.Manatreat:BAAANQAECgIIAwABNQAECgoKLwAFAPwXAA==.Manuall:BAAANQAECgQICQAAAA==.Marbas:BAABNQAECn8eAAIGAAgKKRyfOABDAgAGAAgKKRyfOABDAgAAAA==.Maxidk:BAABNQAECn83AAILAAkKlyMcAgCZAgALAAkKlyMcAgCZAgAAAA==.Maximage:BAAANQAECgQICAABNQAECgkJNwALAJcjAA==.Maximonk:BAAANQADCgQIBgABNQAECgkJNwALAJcjAA==.Mazëkeen:BAAANQADCggICAAAAA==.',
Me='Meditare:BAAANQABCgIIAgAAAA==.Medîvh:BAABNQAECn8ZAAIgAAkKrwu1xwD2AQAgAAkKrwu1xwD2AQAAAA==.',
Mi='Midgemaisel:BAAANQAECgYIEwAAAA==.Mik:BAAANQABCgMIAgABNQADCgYJBgATAAAAAA==.Mikhael:BAAANQADCgEIAQABNQADCgYJBgATAAAAAA==.Mirado:BAABNQAECn8nAAISAAoKXx76BQC2AgASAAoKXx76BQC2AgAAAA==.Mirix:BAAANQADCgUIBQAAAA==.Mithridates:BAABNQAECn8oAAIUAAkKQwgsGwCTAQAUAAkKQwgsGwCTAQAAAA==.',
Mo='Monix:BAABNQAECn8lAAMLAAoKFxQsOwAYAgALAAkK8BUsOwAYAgAGAAYKTw5zhgAHAQAAAA==.Monkragga:BAABNQAECn8YAAIOAAgKQhbuBgCgAQAOAAgKQhbuBgCgAQAAAA==.Mooseleroy:BAABNQAECn8eAAQOAAcKkRJFLgCmAQAOAAcKkRJFLgCmAQAiAAIK8QTlRwBKAAAeAAEKfQWENQAiAAAAAA==.Moriko:BAAANQAECgEIAQABNQAECgYIDwATAAAAAA==.Mortarien:BAABNQAECn8lAAMHAAoKYhlhFQBeAQAGAAcKTRzDUwDDAQAHAAgKARZhFQBeAQAAAA==.Mozai:BAAANQADCgIIAgABNQAECggIGAADAFceAA==.',
Mu='Mugged:BAABNQAECn8lAAMgAAoKPwzqMwBXAQAgAAoKPwzqMwBXAQAhAAIKoQPNNgBhAAAAAA==.',
My='Myrtle:BAABNQAECn8vAAImAAkKdROsAwBuAQAmAAkKdROsAwBuAQAAAA==.',
['Má']='Másóchist:BAABNQAECn8gAAMQAAkKbB7ERACEAgAQAAgKBh3ERACEAgAUAAIKxSAARAC1AAAAAA==.',
Na='Naraela:BAAANQAECgQIBAAAAA==.Naturi:BAAANQADCgYIBgAAAA==.',
Ne='Necrophobic:BAAANQADCgQIBAAAAA==.Nevernude:BAAANQAECgQIBAABNQAECgoKMAABALIeAA==.',
Ni='Nice:BAAANQADCgYIDAAAAA==.Nikna:BAAANQADCgIIAgAAAA==.Niwatori:BAABNQAECn8tAAIIAAkK9x0KAwBUAgAIAAkK9x0KAwBUAgAAAA==.',
No='Noah:BAACNQAFFH8cAAMkAAcKfh4zAABaAgAkAAYKgCEzAABaAgAZAAQK+A7kEgASAQA1AAQKfyMAAyQACQocJnABAFoDACQACQocJnABAFoDABkAAgrJFKVuAHYAAAAA.Nol:BAAANQAECggICgABNQAFFAgIIQAJAMMiAA==.Nolarz:BAACNQAFFH8hAAIJAAgKwyJBAQC1AgAJAAgKwyJBAQC1AgA1AAQKfywAAgkACgqAJYEEAI4DAAkACgqAJYEEAI4DAAAA.',
Nu='Nukthom:BAAANQADCgcICQAAAA==.',
Ny='Nyneaves:BAABNQAECn8zAAIWAAoKwBvEAQBaAgAWAAoKwBvEAQBaAgAAAA==.Nyst:BAABNQAECn8dAAIgAAgK0RLJwwD9AQAgAAgK0RLJwwD9AQAAAA==.Nyxnecrocog:BAAANQADCgIIAgAAAA==.',
Ob='Objekt:BAAANQAECgYICAAAAA==.',
Oh='Ohmenwah:BAAANQADCgUICQAAAA==.',
Oj='Ojplosion:BAACNQAFFH8GAAIQAAIKlx7uKQC3AAAQAAIKlx7uKQC3AAA1AAQKfxsAAxAACQojI2YxAMICABAACAqvI2YxAMICABQAAwqeHpw0APEAAAE1AAQKBggHABMAAAAA.Ojpyroblast:BAAANQAECgYIBwAAAA==.',
Ol='Olga:BAAANQAECgcIDAAAAA==.Olma:BAABNQAECn8aAAIMAAYKUBAlbgC+AAAMAAYKUBAlbgC+AAABNQAFFAcIIgAXAKYgAA==.',
Om='Omghunter:BAAANQADCggICAAAAA==.',
On='Onisprite:BAAANQAECgQICAAAAA==.',
Or='Orchaos:BAAANQADCgUIBgAAAA==.Ordhah:BAABNQAECn8iAAQDAAoKIiAMQwDLAgADAAkKYyEMQwDLAgAEAAIKUQmEbgBwAAAVAAEK1RYkbAA6AAAAAA==.',
Os='Osanna:BAAANQADCggJFQAAAA==.',
Ou='Ourlastlock:BAAANQADCggICAAAAA==.',
Pa='Paladout:BAABNQAECn8tAAMDAAoKEx8+HwClAQADAAoKpB4+HwClAQAVAAQKxB9uKwCCAQAAAA==.Palagouge:BAAANQAECgEIAQAAAA==.Palletjack:BAABNQAECn83AAILAAoKEyY3AQDkAwALAAoKEyY3AQDkAwAAAA==.Palli:BAAANQADCggIFwAAAA==.Paona:BAABNQAECn8tAAIIAAoKgAsQDACCAQAIAAoKgAsQDACCAQAAAA==.Papafloppa:BAAANQADCgIIAgAAAA==.Paperpuppy:BAAANQADCgEIAQABNQAECggIFgAgAPMNAA==.Paulioo:BAAANQABCgQIBAAAAA==.',
Pe='Peraroll:BAAANQADCggICAAAAA==.Pewpewkuchoo:BAAANQAECgQIBAAAAA==.',
Ph='Phenphen:BAABNQAECn8oAAMJAAoKjyMDCwAyAwAJAAgKqSMDCwAyAwAKAAYKqBV+MQAxAQAAAA==.Physicyan:BAABNQAECn8eAAQXAAkKXw7nDwD6AQAXAAkKXw7nDwD6AQAYAAEKVwWXLAArAAAWAAEKZgJ3gAAqAAAAAA==.',
Pi='Pipez:BAAANQAECgYIDgAAAA==.',
Pl='Planetdru:BAABNQAECn8lAAIIAAkK5B2mJQClAgAIAAkK5B2mJQClAgAAAA==.',
Po='Pogster:BAAANQADCgcIBwAAAA==.Pollyy:BAABNQAECn8gAAIGAAcKoQmzcABTAQAGAAcKoQmzcABTAQAAAA==.Popshampain:BAABNQAECn8dAAIPAAcKTxMoegC0AQAPAAcKTxMoegC0AQAAAA==.',
Ps='Psychonight:BAABNQAECn8kAAIYAAkKpBpOAwDCAgAYAAkKpBpOAwDCAgAAAA==.',
Pu='Punchydabear:BAAANQAECgUIAQAAAA==.',
['Pì']='Pìp:BAAANQADCgYJBgAAAA==.',
Ra='Raenlling:BAAANQAFFAIIAwAAAA==.Ratscum:BAEANQADCggIGAAAAA==.Rayssa:BAABNQAECn82AAMYAAgKeCR1AQA6AwAYAAgKpSN1AQA6AwAXAAcKNyDcBQCdAgAAAA==.',
Re='Redeker:BAABNQAECn8oAAIJAAoKShEvDABoAQAJAAoKShEvDABoAQAAAA==.Redlossa:BAAANQADCgIIAgAAAA==.Renneth:BAAANQADCgUICgAAAA==.Rentahunter:BAAANQAECgEIAQAAAA==.Revax:BAAANQAECgQIBQABNQAECgoKLwAFAPwXAA==.Reyna:BAAANQADCgQIBAABNQADCggICAATAAAAAA==.',
Rh='Rhavin:BAAANQADCgIIAgAAAA==.Rholand:BAAANQAECgUIBgAAAA==.',
Ri='Ricopsu:BAABNQAECn8lAAMfAAoKOR36AgC3AQAfAAoKOR36AgC3AQAIAAEKygYyuQAnAAAAAA==.',
Rn='Rngnar:BAAANQAECggIEQAAAA==.',
Ro='Roakar:BAAANQAECgQIBwAAAA==.Rocklii:BAAANQAECgEIAQAAAA==.Roguewolf:BAABNQAECn83AAMIAAoKGxHPCQCeAQAIAAkK+xDPCQCeAQACAAEKcQUKeQAtAAAAAA==.Rokdomaa:BAAANQAFFAEIAQAAAA==.Roki:BAABNQAECn8eAAIaAAkKmBBGIQDGAQAaAAkKmBBGIQDGAQAAAA==.Rolow:BAABNQAECn81AAIgAAkKqhuODAAKAgAgAAkKqhuODAAKAgAAAA==.Roony:BAACNQAFFH8cAAICAAgKgB5mAQB2AgACAAgKgB5mAQB2AgA1AAQKfygAAgIACgp0IDwLABYDAAIACgp0IDwLABYDAAAA.Roper:BAAANQAECggIBAAAAA==.Roritai:BAAANQABCgQIBAABNQAECgQICwATAAAAAA==.Rot:BAABNQAECn8kAAMHAAkKyCXXDwARAwAHAAgKJSXXDwARAwAGAAkKZCQsFgAJAwAAAA==.Royle:BAABNQAECn8nAAQMAAoKVRp+DgDmAQASAAgKzxtJBwCGAgAMAAkKsRV+DgDmAQAjAAEKAACjQwAzAAAAAA==.',
Ru='Runes:BAABNQAECn8vAAIGAAoKvhdxKACYAgAGAAoKvhdxKACYAgAAAA==.Runnerjay:BAABNQAECn8bAAIFAAoKzAatWAD9AAAFAAoKzAatWAD9AAABNQAECgoKKwAVAA8SAA==.Rush:BAAANQADCgIIAgABNQAECgoKLAABADMXAA==.Ruuf:BAABNQAECn8fAAMVAAoK8iI/DADWAgAVAAoK8iI/DADWAgADAAYK9wa2JgHfAAAAAA==.',
Ry='Rygik:BAAANQAECgYIDQABNQAECgoKIAAZAFAfAA==.Rysxn:BAABNQAECn8gAAMZAAoKUB9HFAC9AgAZAAkKux9HFAC9AgAFAAEKYRzDrABaAAAAAA==.Ryuujins:BAACNQAFFH8iAAIXAAcKpiDSAACNAgAXAAcKpiDSAACNAgA1AAQKfycAAxcACgrqJJ4aAAkDABcACgqmJJ4aAAkDABgABQq/JE0JAMQBAAAA.',
['Rá']='Ráhu:BAAANQAECgUICgABNQAECgoKMQARAOsbAA==.',
Sa='Sago:BAABNQAECn8hAAMMAAoK+x/JVQCJAgAMAAoKUB/JVQCJAgAjAAUK6hpmHgBhAQAAAA==.Sandman:BAABNQAECn8ZAAIDAAgKGRC8uACsAQADAAgKGRC8uACsAQAAAA==.Sausage:BAAANQABCgQIBAAAAA==.',
Sc='Scumball:BAEANQADCgcIEgABNQADCggIGAATAAAAAA==.Scyon:BAACNQAFFH8HAAIgAAQKFQ1HKwAzAQAgAAQKFQ1HKwAzAQA1AAQKf08AAiAACgoVIMsHAE8CACAACgoVIMsHAE8CAAAA.',
Se='Selinie:BAAANQABCggIEAAAAA==.Senari:BAABNQAECn8oAAMVAAgKahvFHgDxAQADAAgKRBfKhgAaAgAVAAcK5RvFHgDxAQAAAA==.Senbane:BAAANQADCggICQAAAA==.Sencia:BAABNQAECn8VAAMGAAgK1xK+ZQB6AQAGAAcKMRK+ZQB6AQAHAAQKcxDaOwC0AAAAAA==.Senseiwacks:BAAANQAECgIIAgAAAA==.',
Sh='Shadowblazer:BAABNQAECn8mAAIQAAkKPh5GDgDTAQAQAAkKPh5GDgDTAQAAAA==.Shalizar:BAAANQAECgYIBgAAAA==.Shanda:BAACNQAFFH8OAAIBAAUKdBzOCgChAQABAAUKdBzOCgChAQA1AAQKfygAAwEACgpIIcIeAPACAAEACgpIIcIeAPACAA8AAwoZIIDYAOMAAAAA.Shanto:BAABNQAECn8uAAIPAAoKYhtoIwD5AgAPAAoKYhtoIwD5AgAAAA==.Shatrauzg:BAAANQAECgcICAAAAA==.Sheesh:BAAANQADCgcIDgAAAA==.Shesheshenn:BAABNQAECn80AAMBAAkKUB5/EQDKAQABAAgKBCJ/EQDKAQANAAkKmgEYKQDUAAAAAA==.Shiftinmojo:BAAANQAECggIEwAAAA==.Shoumei:BAABNQAECn8mAAMOAAkK4xZfIAAqAgAOAAkK4xZfIAAqAgAiAAYKAAqvLAAGAQAAAA==.Shugz:BAAANQAECgEIAQABNQAFFAUIBgAKANIUAA==.Shuken:BAAANQAECggIAQAAAA==.',
Si='Silfra:BAAANQAECgQIDAAAAA==.Sinfull:BAAANQADCggICAAAAA==.Sintharia:BAAANQAECgYIBgAAAA==.Siousxie:BAAANQADCgUICAAAAA==.',
Sk='Skolaid:BAACNQAFFH8OAAMEAAQKnQxlEwArAQAEAAQKnQxlEwArAQADAAMKox4fBQALAQA1AAQKfywAAwQACgoCHhAVACwDAAQACQqfIBAVACwDAAMABwpeIwRpAGECAAAA.',
Sl='Slapparazzi:BAAANQADCgYIBQAAAA==.',
Sm='Smilingdev:BAAANQADCggIEAABNQAECgMIAwATAAAAAA==.Smoopoodoop:BAAANQAECgcIDAAAAA==.',
Sn='Snagglepuss:BAAANQAECgQIBAAAAA==.Sneakysin:BAAANQADCgQIBAAAAA==.',
So='Soulmend:BAAANQAECgYIEQAAAA==.Soulsproxy:BAAANQABCgQIBQAAAA==.',
Sp='Spaceman:BAAANQAECgUIDAAAAA==.',
Sq='Sqûïsh:BAAANQADCggICAAAAA==.',
St='Stabbz:BAAANQADCgUIBQAAAA==.Stevetson:BAAANQAECgYIDQAAAA==.Stonatroll:BAAANQAECgMIBAABNQAECgoKLwAFAPwXAA==.Stoops:BAAANQADCggIFgAAAA==.Stormdemon:BAABNQAECn8mAAMMAAkKyhVrKABlAQAMAAkKgBVrKABlAQASAAEKrxq8EwBQAAAAAA==.Stormspellz:BAABNQAECn8jAAIBAAoKYhU8IwBZAQABAAoKYhU8IwBZAQAAAA==.',
Su='Supay:BAABNQAECn8XAAImAAcKThHvBgANAQAmAAcKThHvBgANAQAAAA==.',
Sw='Swinginsista:BAABNQAECn8lAAIEAAkKsRuoCAA5AgAEAAkKsRuoCAA5AgAAAA==.',
Ta='Taldath:BAAANQADCggJDwAAAA==.Talicso:BAACNQAFFH8GAAMgAAMKTgpgSgCTAAAgAAIKlg1gSgCTAAAhAAEKvANCFQBBAAA1AAQKfyAAAiAACQpbGWeKAGoCACAACQpbGWeKAGoCAAAA.Talos:BAAANQAECggIEgAAAA==.Talzinn:BAAANQADCgYIBgABNQAECggIEgATAAAAAA==.Tardalian:BAAANQADCgYICAAAAA==.Tarkinal:BAABNQAECn8cAAMBAAkKwhu8KwC0AgABAAkKwhu8KwC0AgAPAAIK+AS3bQBjAAAAAA==.Taurito:BAAANQAECgUIDgAAAA==.',
Te='Teezee:BAABNQAECn80AAMDAAoK9R2oCwAoAgADAAoK9R2oCwAoAgAEAAMKKBPQ3ADFAAAAAA==.Teitterdrud:BAABNQAECn8dAAMIAAgK1A3LUgCQAQAIAAgKGwrLUgCQAQAfAAMK1RIjKwC4AAAAAA==.Telina:BAAANQAECggIDQAAAA==.Telira:BAABNQAECn8cAAMWAAoKFxEGAwD0AQAWAAoKFxEGAwD0AQAXAAEK7QKx/gAuAAAAAA==.Tenderhoof:BAACNQAFFH8KAAIIAAQKhBBWCADWAAAIAAQKhBBWCADWAAA1AAQKfy8AAwgACgrzHRwTAC4DAAgACgrzHRwTAC4DAAIABwpxEX0uAKcBAAAA.',
Th='Thanatus:BAAANQADCgQJBAAAAA==.Thath:BAAANQADCggIJwAAAA==.Thavus:BAAANQADCgYIBgAAAA==.Thearatwo:BAABNQAECn8eAAILAAoKoCEZCgBkAwALAAoKoCEZCgBkAwAAAA==.Thruumm:BAAANQAECgcIDQAAAA==.Thunderclapz:BAAANQAECgcJCAAAAA==.Thunsibution:BAAANQADCggICQABNQAFFAUIDwAjAKEbAA==.',
Ti='Tickz:BAABNQAECn8zAAQQAAkKFR/1CAAXAgAQAAkK8h71CAAXAgAcAAYKmB5FCQDwAQAUAAIKwBUJVACCAAAAAA==.Tinilia:BAAANQADCgQIBQAAAA==.Tirah:BAABNQAECn80AAIIAAgKlwnxEwA7AQAIAAgKlwnxEwA7AQAAAA==.',
To='Toat:BAAANQADCgYIBgAAAA==.Toeran:BAABNQAECn81AAMVAAoKVxwsAQCjAgAVAAoKVxwsAQCjAgADAAUK+A5qBgEUAQAAAA==.Tokémon:BAAANQAECgcICgAAAA==.Toxren:BAACNQAFFH8GAAIEAAIKwRAQIACOAAAEAAIKwRAQIACOAAA1AAQKfyYAAwQACgrUHAshAOoCAAQACgrUHAshAOoCAAMAAgoSBdSPAUQAAAAA.',
Tr='Traelin:BAACNQAFFH8PAAIEAAUKVxzdAwCQAQAEAAUKVxzdAwCQAQA1AAQKfygAAgQACgrGIl8GAJkDAAQACgrGIl8GAJkDAAAA.Tread:BAAANQAECgMIAwAAAA==.Trickee:BAAANQAECgYICwABNQAECgcIFAALAGshAA==.',
Ts='Tskaha:BAAANQAFFAEIAQAAAA==.',
Ty='Tyelonolkid:BAAANQAECgMIAwAAAA==.Tyria:BAABNQAECn8hAAIZAAoKgAwUCQBSAQAZAAoKgAwUCQBSAQAAAA==.Tyruunas:BAAANQADCgMIAwAAAA==.',
Ug='Uggthok:BAABNQAECn8bAAMGAAgKvhAzEQBSAQAGAAgKvhAzEQBSAQALAAEKMAC5cgANAAAAAA==.',
Ur='Urizarah:BAAANQADCgYIDAAAAA==.',
Ut='Uthrid:BAAANQADCgYIDAAAAA==.',
Va='Vanadis:BAAANQADCgcICwAAAA==.Vardamir:BAACNQAFFH8MAAIEAAUK3xAxCAAFAQAEAAUK3xAxCAAFAQA1AAQKfyYAAgQACgpuH0seAPgCAAQACgpuH0seAPgCAAAA.Vargath:BAAANQADCgQIBAAAAA==.Vashstampede:BAAANQAECgYICAAAAA==.',
Ve='Vei:BAAANQAECggICAABNQADCgIIAgATAAAAAA==.Velrik:BAAANQAECgQICgAAAA==.Venema:BAAANQADCgIIAgAAAA==.Venüs:BAAANQAECgEIAQAAAA==.Vercy:BAAANQADCgYIBwABNQAECgMIBAATAAAAAA==.Vezkin:BAACNQAFFH8PAAIIAAUKtCHGBAAcAQAIAAUKtCHGBAAcAQA1AAQKfycAAggACgqCJZsJAIEDAAgACgqCJZsJAIEDAAAA.',
Vh='Vhexx:BAAANQAECgQIBAAAAA==.',
Vi='Vintagejeans:BAABNQAECn8ZAAIDAAcK+QPFGwHxAAADAAcK+QPFGwHxAAAAAA==.Virtus:BAABNQAECn8qAAIFAAkKxBfqPQCwAgAFAAkKxBfqPQCwAgAAAA==.Vitrixz:BAAANQADCgUICwAAAA==.Vizaimor:BAABNQAECn8dAAIFAAkKYRH7aABCAgAFAAkKYRH7aABCAgAAAA==.',
Vo='Voi:BAAANQABCgcICQABNQAECgEIAQATAAAAAA==.Vostok:BAACNQAFFH8GAAIMAAQKZw61HAAsAQAMAAQKZw61HAAsAQA1AAQKfyQAAwwACgppGIk4ADYBAAwACgppGIk4ADYBACMAAQoxE7tCADUAAAAA.',
Vu='Vulcãnus:BAAANQAECgEIAgAAAA==.',
Wa='Wallyoak:BAAANQADCgEIAQAAAA==.Warcry:BAAANQAECgEJAQAAAA==.',
We='Wealthyscaly:BAAANQAECgMIBwAAAA==.Weedzzar:BAAANQADCgQIBgAAAA==.Werse:BAABNQAECn8tAAIXAAoKAB10HQCSAQAXAAoKAB10HQCSAQAAAA==.Wetloginyou:BAABNQAECn8jAAIBAAgKySA0CwASAgABAAgKySA0CwASAgAAAA==.',
Wh='Whodi:BAABNQAECn8WAAQgAAgK8w1LFwFlAQAgAAYKLwxLFwFlAQAnAAIKRgtsCQBzAAAhAAIKahCcMwBsAAAAAA==.',
Wi='Witt:BAABNQAECn8aAAMUAAgKFAg2LQAYAQAQAAYK5Aay1gAcAQAUAAUK4Ag2LQAYAQAAAA==.',
Wo='Woementality:BAAANQADCgMIAwAAAA==.Wolful:BAABNQAECn8sAAMBAAoKMxdtEgDCAQABAAoKMxdtEgDCAQANAAMKbQU1LQCUAAAAAA==.',
Wr='Wrathoftitan:BAAANQADCgIIAgAAAA==.',
Wu='Wubble:BAAANQAECgQIBAAAAA==.Wushoolay:BAAANQAECgQJCgAAAA==.',
Xn='Xnatem:BAABNQAECn8sAAIjAAkKVCERBwDuAgAjAAkKVCERBwDuAgAAAA==.',
Xo='Xoliver:BAAANQADCgYICQAAAA==.',
Ya='Yashiro:BAABNQAECn8rAAMEAAoKfg9IZwDiAQAEAAoKfg9IZwDiAQADAAEKAADR1AEbAAAAAA==.',
Ye='Yeraleth:BAABNQAECn8lAAICAAoKpBvVEQDDAgACAAoKpBvVEQDDAgAAAA==.',
Yi='Yisiwang:BAAANQADCgcIBwABNQAECgMIBAATAAAAAA==.',
Yo='Yorick:BAAANQADCggIFQAAAA==.Yorkj:BAABNQAECn8aAAIHAAoKmQhGLQDnAAAHAAoKmQhGLQDnAAAAAA==.',
Za='Zalthorax:BAAANQAECgUIDAABNQAECgoKLwAFAPwXAA==.Zatilion:BAABNQAECn8jAAIDAAkKJxHONwBaAQADAAkKJxHONwBaAQAAAA==.Zavage:BAAANQADCgYICgABNQAECggIJAAQALkQAA==.Zayn:BAAANQAECgUIDAAAAA==.',
Ze='Zedon:BAABNQAECn8mAAMbAAkKyBMBIABWAQAbAAYKIg4BIABWAQAaAAYKORNgCgAcAQABNQAECgkJJgAbAMgTAA==.Zenki:BAAANQAECggICAAAAA==.Zenkî:BAAANQADCgEIAQAAAA==.Zenrune:BAAANQAECgcICgABNQAECgkJFQAKANkRAA==.Zephiday:BAAANQAECgMIAwAAAA==.',
Zi='Ziggamoo:BAAANQADCggIEgABNQAECgoKMAAFADseAA==.Ziggashot:BAABNQAECn8wAAIFAAoKOx4nFQBIAwAFAAoKOx4nFQBIAwAAAA==.Zinsus:BAAANQAECgcIDQABNQAECgoKLwAFAPwXAA==.',
Zo='Zongchi:BAAANQAECgEIAQAAAA==.Zoomzoom:BAAANQABCgMIAQAAAA==.',
Zu='Zurahahsha:BAABNQAECn8wAAINAAkKMAV2CQBdAQANAAkKMAV2CQBdAQAAAA==.',
['Ðr']='Ðrow:BAABNQAECn8hAAIZAAkKDAyyBQCSAQAZAAkKDAyyBQCSAQAAAA==.',
['Óx']='Óxy:BAABNQAECn8kAAIUAAkKbBCDAQB/AQAUAAkKbBCDAQB/AQAAAA==.',
['Ör']='Örc:BAAANQAECgMIAwABNQAECgoKIgADACIgAA==.',
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

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

local lookup = {'Rogue-Assassination','Paladin-Holy','Unknown-Unknown','Hunter-BeastMastery','Paladin-Retribution','Druid-Feral','Druid-Guardian','Shaman-Elemental','Warlock-Demonology','DeathKnight-Blood','Evoker-Preservation','Paladin-Protection','Mage-Frost','Rogue-Subtlety','DemonHunter-Havoc','Druid-Restoration','Warrior-Arms','Shaman-Restoration','Monk-Mistweaver','Monk-Windwalker','Hunter-Survival','Hunter-Marksmanship','Warlock-Affliction','Warlock-Destruction','Evoker-Devastation','DeathKnight-Unholy','DeathKnight-Frost','DemonHunter-Devourer','Mage-Arcane','DemonHunter-Vengeance','Priest-Holy','Priest-Shadow','Warrior-Fury','Monk-Brewmaster','Warrior-Protection','Shaman-Enhancement','Druid-Balance','Evoker-Augmentation',}
local provider = {region='US',realm='KhazModan',name='US',type='weekly',zone=53,date='2026-11-03',data={Ad='Adorelle:BAAANQADCgEIAQABNQAECgoKLQABAMkaAA==.Advîl:BAABNQAECn8tAAICAAoKDR0gFADrAgACAAoKDR0gFADrAgAAAA==.',
Ae='Aeryhnn:BAAANQADCgcIHwABNQAECgQIEwADAAAAAA==.',
Ag='Aglet:BAAANQADCgEIAQAAAA==.',
Al='Alarogue:BAAANQAECgYICAAAAA==.Alexandre:BAABNQAECn8gAAIEAAkKtxFqlgDbAQAEAAkKtxFqlgDbAQAAAA==.Allasia:BAAANQADCgYIBwAAAA==.Alterboy:BAAANQADCgIIAgABNQAECggIKgACAJghAA==.Alton:BAABNQAECn8xAAICAAoKSg9hWAAQAgACAAoKSg9hWAAQAgAAAA==.',
Am='Amoonsia:BAAANQAECgQIBgAAAA==.',
An='Anfernyphere:BAABNQAECn8VAAMCAAgKyx7VLQCvAgACAAgKyx7VLQCvAgAFAAQK8w/PHwHqAAABNQAECgQIBQADAAAAAA==.Ansuz:BAAANQAECgIIAwAAAA==.Anvil:BAAANQADCgMIAwAAAA==.',
Ap='Aphroditee:BAAANQADCgUIBgAAAA==.Apostriss:BAAANQADCgMIAwAAAA==.',
Aq='Aquafresh:BAAANQADCgUJBQAAAA==.',
Ar='Arisel:BAABNQAECn8jAAMGAAgKUBOYEQBfAQAGAAgKUBOYEQBfAQAHAAYKRwtGMwAHAQAAAA==.Aristia:BAAANQADCggIDgABNQAFFAIIBgAIAGwCAA==.Arweni:BAAANQAECgIIAQAAAA==.',
At='Atheizt:BAABNQAECn8eAAICAAkKcRtgJwDLAgACAAkKcRtgJwDLAgAAAA==.',
Az='Azael:BAAANQADCgcIEQAAAA==.',
Ba='Badned:BAAANQAECggICQAAAA==.Bakachan:BAAANQAECgIIAgAAAA==.Baldilocks:BAAANQADCgQIBAAAAA==.Ballia:BAAANQAECgEIAQAAAA==.Banedon:BAAANQADCgMJBwABNQAECggIKgACAJghAA==.',
Be='Bearbacked:BAAANQADCgYIBgABNQAECgUIDgADAAAAAA==.Beastmaster:BAAANQAECgMIAwAAAA==.Beetingu:BAAANQADCgcIFgABNQAECggIIAAJAHkjAA==.Belashar:BAAANQADCgYIGAAAAA==.Beytuha:BAABNQAECn8zAAIHAAkKqSVKBwASAwAHAAkKqSVKBwASAwAAAA==.',
Bi='Bighornygay:BAAANQAECggIBQAAAA==.Bigsmoke:BAAANQADCgUIBQAAAA==.',
Bl='Blacken:BAABNQAECn8gAAIKAAcK6xmXNgBBAQAKAAcK6xmXNgBBAQAAAA==.Blackknife:BAAANQADCgQIBAAAAA==.Bladestorm:BAAANQAECgQIBwABNQAFFAMICQALAD0dAA==.Blakylightz:BAABNQAECn8bAAMFAAkKwhqDTQANAgAFAAgKRhmDTQANAgAMAAQKqh0+HQBPAQABNQAFFAIIBAADAAAAAA==.Blazen:BAABNQAECn8rAAIIAAoKESB/IAAJAwAIAAoKESB/IAAJAwAAAA==.Blinker:BAABNQAECn8aAAINAAgKwwuYGAAzAQANAAgKwwuYGAAzAQAAAA==.Bloodynuts:BAABNQAECn8cAAMOAAkKqhOAFwAiAgAOAAgKURSAFwAiAgABAAIKzhImjwB1AAAAAA==.Bloyfbloyf:BAACNQAFFH8HAAIPAAQKzgTqDgCjAAAPAAQKzgTqDgCjAAA1AAQKfywAAg8ACgoBGbkTAFQCAA8ACgoBGbkTAFQCAAAA.Blueberriess:BAAANQAECgQIBAAAAA==.Bluemental:BAAANQAECgEIAQAAAA==.Blueshadøw:BAAANQAECgEIAgAAAA==.',
Bo='Bobbidyboo:BAACNQAFFH8YAAIQAAUKSgfCBwAtAQAQAAUKSgfCBwAtAQA1AAQKf0EAAhAACgoVE+4kAPwBABAACgoVE+4kAPwBAAAA.Bokbokchickn:BAAANQADCgEIAQAAAA==.Bonesclone:BAAANQAECgMIAgAAAA==.',
Br='Brewshido:BAAANQAECgMIBgAAAA==.Briareosx:BAABNQAECn84AAIRAAoKeBv8SACvAgARAAoKeBv8SACvAgAAAA==.Brixtia:BAAANQADCgcIBwABNQAECgkJLgAEAFQaAA==.Brovar:BAACNQAFFH8aAAIFAAUKzSC1CwCOAQAFAAUKzSC1CwCOAQA1AAQKf0EAAgUACgrEIzIWAGwDAAUACgrEIzIWAGwDAAAA.',
Bu='Bubbaa:BAABNQAECn8hAAMSAAkKrR/+IQDgAgASAAkKrR/+IQDgAgAIAAEKAAAMJAFJAAAAAA==.Buddydaelf:BAABNQAECn8iAAIEAAoKnxXKXwBXAgAEAAoKnxXKXwBXAgAAAA==.',
Bw='Bwonsamdî:BAAANQAECgIIAwAAAA==.Bwonshlongdi:BAAANQADCgYIBgAAAA==.',
Ca='Cathexis:BAAANQADCggIEgABNQAECgkJLAALAGIQAA==.',
Ce='Ceanaflowers:BAABNQAECn8ZAAIRAAoKrRBwjAD9AQARAAoKrRBwjAD9AQAAAA==.',
Ch='Challah:BAAANQAECgIIBgAAAA==.Chia:BAABNQAECn8sAAMTAAkK2RaIDgDwAQATAAkK2RaIDgDwAQAUAAIKnQaEYQBZAAABNQADCgMIBAADAAAAAA==.Chianamoya:BAAANQADCgcIEgABNQAECgQIEwADAAAAAA==.Chune:BAAANQADCgQIBAAAAA==.',
Cl='Clairvoyant:BAAANQAECgEIAQAAAA==.Clarisse:BAAANQAECgIIAwABNQAECgoKPgAKAE0aAA==.',
Co='Coldburn:BAAANQADCgQIBAAAAA==.Connor:BAAANQAECgQIDAAAAA==.Coolarrow:BAABNQAECn8tAAIEAAkKPxtzJACEAgAEAAkKPxtzJACEAgABNQAFFAQIFAAEAB4fAA==.Cosby:BAAANQABCgMIBQAAAA==.',
Cr='Cracken:BAAANQADCgEIAgAAAA==.Croissantx:BAAANQAECgUIEwAAAA==.Crosshair:BAABNQAECn8ZAAMVAAYKvxC0CQCQAQAVAAYKvxC0CQCQAQAWAAEKXAHingAfAAAAAA==.',
Cu='Cutpo:BAAANQAECgQIBAABNQAFFAcIFQAJAMIQAA==.',
Cy='Cyndrenissa:BAAANQADCgEIAQAAAA==.Cynris:BAAANQAECgEIAQABNQAECgoKNwAMAJ8eAA==.',
['Cê']='Cêlaçane:BAAANQADCgIJAwAAAA==.',
Da='Dacianstorm:BAAANQADCgIIAgAAAA==.Dacianwolf:BAAANQAECggIDQAAAA==.Dagaz:BAAANQADCgUICAAAAA==.Daravinius:BAAANQAECgYIDgAAAA==.Dare:BAAANQAECgQJBwAAAA==.Davaeh:BAAANQADCgIIAgABNQAECggIKgACAJghAA==.Davandar:BAAANQADCgYIDAAAAA==.Daveah:BAABNQAECn8pAAISAAgKzAltagBCAQASAAgKzAltagBCAQAAAA==.',
De='Deadex:BAAANQADCgEIAQAAAA==.Deathberry:BAABNQAECn8sAAIJAAgK6AxukAC9AQAJAAgK6AxukAC9AQAAAA==.Deathsmoke:BAAANQADCgEIAQAAAA==.Delphron:BAAANQAECgIIBAAAAA==.Demoncharge:BAAANQAECgEIAgAAAA==.Demonflayer:BAAANQAECgEIAQABNQAECgEIAgADAAAAAA==.Demonikat:BAAANQADCgMJAwAAAA==.Demonlust:BAAANQAECgEIAQABNQAECgEIAgADAAAAAA==.Denaeaa:BAABNQAECn8YAAMTAAcKYBeXGQDmAQATAAcKYBeXGQDmAQAUAAIKlgB2WAAkAAABNQAFFAQICAASAIAFAA==.Depala:BAAANQADCgcIEQABNQAECgIIAgADAAAAAA==.Devilzkry:BAAANQADCgUIBQAAAA==.Devistaysha:BAABNQAECn82AAMIAAoKJBNKMADhAQAIAAoKJBNKMADhAQASAAEKvgFA9QAhAAAAAA==.',
Dh='Dharmakat:BAAANQADCgUICQAAAA==.',
Di='Dist:BAAANQAECgMICQAAAA==.Divinestorm:BAABNQAECn8qAAMCAAgKmCEoFQDjAgACAAgKmCEoFQDjAgAFAAYKEA0wCAERAQAAAA==.Divinethis:BAAANQADCgIIAwAAAA==.',
Dn='Dnyal:BAAANQAECggIEAAAAA==.',
Do='Dodgysenpai:BAAANQADCgUIBQABNQAECgoKPwARAJUmAA==.Dogbreathrlz:BAAANQABCgUIBwAAAA==.Dolomite:BAAANQAECgMIBgAAAA==.Dookerslol:BAAANQADCgUIAwAAAA==.Dotexe:BAABNQAECn8pAAIBAAcKsB5wDwCuAQABAAcKsB5wDwCuAQAAAA==.Dotsy:BAACNQAFFH8dAAQXAAYK8R2rAABrAQAXAAYK8R2rAABrAQAJAAQKMx+sGwCkAAAYAAEKlxOOGgBQAAA1AAQKf0EABBgACgqjIVgTANcBAAkACQrPIJUzALsCABgABgoXH1gTANcBABcABwqUHuAJAGMBAAAA.',
Dr='Drackarys:BAAANQADCgcIIgAAAA==.Dragooner:BAAANQADCgMIAwAAAA==.Drakiir:BAACNQAFFH8JAAMLAAMKPR2ZCwDxAAALAAMKPR2ZCwDxAAAZAAIKCSOIAwC0AAA1AAQKf0AAAwsACgqxIU4DAIMDAAsACgqxIU4DAIMDABkACAqpIH4PAGICAAAA.Dralkish:BAAANQAECgEIAQAAAA==.Drathi:BAABNQAECn8sAAMLAAkKYhAtIgC6AQALAAkKYhAtIgC6AQAZAAcKcw2QIQBCAQAAAA==.Dravas:BAAANQAECgUICwAAAA==.Draxis:BAAANQADCggIDgAAAA==.Drezzo:BAAANQADCgcIFgAAAA==.Dryerbro:BAAANQABCgUIBQAAAA==.Drzark:BAAANQAECgQIEAAAAA==.',
Du='Duskwulf:BAAANQADCgMIBQABNQAECggIIAASACQcAA==.',
Dw='Dwdog:BAABNQAECn8fAAIXAAgKJBFMBwCuAQAXAAgKJBFMBwCuAQAAAA==.',
['Dà']='Dàthguy:BAABNQAECn9AAAIaAAoK/CNpAwC+AwAaAAoK/CNpAwC+AwAAAA==.',
['Dé']='Défault:BAABNQAECn8yAAMaAAoKIh4wEwAfAwAaAAoKIh4wEwAfAwAbAAQKOA0hcwDTAAAAAA==.',
Ea='Earthgirl:BAAANQADCgEIAQAAAA==.',
Ed='Edaras:BAAANQAECgIIAwAAAA==.',
Ef='Effrøn:BAAANQAECgUIBgAAAA==.',
El='Elek:BAAANQAECgYICwABNQAFFAUIBwAYAIsRAA==.Elennie:BAAANQAECgIIAgAAAA==.Elista:BAAANQADCgEIAQAAAA==.',
Em='Emmi:BAABNQAECn8gAAIaAAgKfRd9IwCTAQAaAAgKfRd9IwCTAQAAAA==.',
En='Enyo:BAABNQAECn8lAAIcAAgK4RUnJgAUAgAcAAgK4RUnJgAUAgAAAA==.',
Er='Erad:BAAANQADCgcIDAAAAA==.',
Ev='Evilritê:BAAANQADCggIEwAAAA==.Evilspawn:BAAANQADCgQIBAAAAA==.',
Ex='Excalipoor:BAAANQADCgIIAQAAAA==.',
Fa='Faloran:BAAANQAECgEIAQAAAA==.Farstad:BAAANQADCgUIBQAAAA==.Fayereadmore:BAAANQADCggICgAAAA==.',
Fe='Fearmyhunter:BAAANQADCggJCQAAAA==.Fekk:BAAANQADCggIDgABNQAECggIDwADAAAAAA==.Felsmoke:BAAANQADCgYIBgAAAA==.Fervid:BAABNQAECn8jAAIdAAgK5RL8kABWAQAdAAgK5RL8kABWAQAAAA==.Feylen:BAABNQAECn8xAAIdAAoK4SUkCgCvAwAdAAoK4SUkCgCvAwAAAA==.',
Fi='Fido:BAABNQAECn8oAAIKAAgKHxHAOwApAQAKAAgKHxHAOwApAQAAAA==.Fidø:BAAANQADCgUIDwABNQAECggIKAAKAB8RAA==.Fifthelement:BAABNQAECn8tAAISAAkKPiGJGADFAgASAAkKPiGJGADFAgAAAA==.Figgson:BAAANQADCgQIBgAAAA==.Figgy:BAABNQAECn8lAAISAAgK7hZ7TQCqAQASAAgK7hZ7TQCqAQAAAA==.Fiorstrasza:BAABNQAECn8jAAMLAAkKYxIHEwCHAQALAAkKYxIHEwCHAQAZAAIKbwZNNgBcAAAAAA==.Firry:BAAANQADCgYIFQAAAA==.Fistsofsmoke:BAAANQADCgUICAAAAA==.',
Fj='Fjalgeirr:BAABNQAECn8zAAMPAAkKGhDUKACIAQAPAAkKGhDUKACIAQAeAAEKAADSPQAFAAAAAA==.',
Fl='Flapers:BAAANQADCgEIAQAAAA==.Flockling:BAAANQADCggIDgAAAA==.',
Fo='Foxymomma:BAABNQAECn8lAAIfAAgKmBgxQQD9AQAfAAgKmBgxQQD9AQAAAA==.',
Fr='Freaksbetter:BAAANQADCgcIBwAAAA==.Froot:BAAANQAECgUIDgAAAA==.Frßlizzard:BAAANQAECgEIAQAAAA==.Frìga:BAAANQADCgUIBgAAAA==.',
Fu='Fulgar:BAABNQAECn88AAIFAAoKHSDGLgAOAwAFAAoKHSDGLgAOAwAAAA==.',
Ga='Galatea:BAAANQAECgUIBQAAAA==.Gankak:BAAANQADCgEIAQAAAA==.Gaëll:BAAANQAECgEIAQAAAA==.',
Ge='Gearsprocket:BAAANQAECggIEgABNQAECgoKMQACAEoPAA==.Geosmin:BAABNQAECn8bAAISAAkKsBAuYwDkAQASAAkKsBAuYwDkAQAAAA==.Geronimoose:BAAANQADCgYJDgABNQAECgoKMQACAEoPAA==.',
Gh='Ghue:BAABNQAECn8cAAMMAAkKpwoPIgAqAQAMAAkKsQgPIgAqAQAFAAYKMwzQAgEbAQAAAA==.Ghòst:BAAANQAECgMIAgAAAA==.',
Gi='Gilalade:BAABNQAECn8gAAIEAAgKBxY9dQCLAQAEAAgKBxY9dQCLAQAAAA==.Girlboss:BAAANQADCgQIBAAAAA==.',
Gl='Glissa:BAAANQAECgIIAgABNQAECgoKKwAZAEcYAA==.',
Go='Gobann:BAAANQAECgUIBgABNQAECgkJLgAEAFQaAA==.Gonern:BAABNQAECn83AAMMAAoKnx7QCgDuAgAMAAoKJB7QCgDuAgAFAAkK+RkEpwDSAQAAAA==.Gooby:BAACNQAFFH8SAAIfAAUKdxY5EACSAQAfAAUKdxY5EACSAQA1AAQKfxsAAx8ACgpmF2E0ADcCAB8ACgpmF2E0ADcCACAAAQrvAImTABUAAAAA.Goond:BAAANQAECgcIDQABNQAFFAUIBwAYAIsRAA==.Gooney:BAAANQAECgQIBgAAAA==.Gotwood:BAAANQADCgYIBgAAAA==.',
Gr='Gravestorm:BAAANQADCgEIAwAAAA==.Grimes:BAAANQADCgcIBwABNQAECgUIDgADAAAAAA==.Grlfriend:BAAANQAECgQICgAAAA==.Grodin:BAAANQAECgUIBgAAAA==.Grofiest:BAABNQAECn8pAAMgAAkK/Q4qGwCAAQAgAAkK/Q4qGwCAAQAfAAEKoAHI7QAbAAAAAA==.',
Gu='Gugg:BAAANQADCgIJAwABNQAECgoKPwARAJUmAA==.Guggychan:BAABNQAECn8/AAMRAAoKlSbpAgDkAwARAAoKdSbpAgDkAwAhAAMKTSbnFQDZAAAAAA==.Guggys:BAAANQAECgQIBQAAAA==.Gunslinger:BAAANQAECggICgAAAA==.Gunsmoke:BAAANQAECgEIAQAAAA==.',
Gw='Gwynbleidd:BAABNQAECn8/AAIKAAoKew/7KQCJAQAKAAoKew/7KQCJAQAAAA==.',
Ha='Hadrian:BAAANQADCgYIEgAAAA==.Haldor:BAAANQADCgcIBwAAAA==.Hanohakua:BAAANQADCgcIDgAAAA==.Haohmaru:BAABNQAECn8lAAIiAAgKwxw9CgByAgAiAAgKwxw9CgByAgAAAA==.Harthen:BAAANQADCgcIGAABNQAECggIIwAGAFATAA==.Hashbrowns:BAAANQADCgIIAgAAAA==.',
He='Heella:BAAANQADCgEIAQAAAA==.Hellßoy:BAAANQADCgUICwAAAA==.Herc:BAAANQAECgIIAgAAAA==.Hercgrim:BAABNQAECn8WAAQhAAcKHhQEGQARAQARAAYK2xBL4AApAQAhAAQKOhsEGQARAQAjAAEK8gyJRwAmAAAAAA==.Hercsham:BAAANQAECgIIAgAAAA==.Herger:BAAANQADCgEIAwAAAA==.',
Hi='Hipsta:BAABNQAECn8gAAIFAAoK7gnU1QBwAQAFAAoK7gnU1QBwAQAAAA==.',
Ho='Hollowshkari:BAAANQADCgYICAAAAA==.Holyclunge:BAAANQAECggIDQAAAA==.Holypower:BAAANQADCgcIBwAAAA==.Holyshocks:BAAANQADCgEIAQAAAA==.Horexion:BAAANQADCgUJBQAAAA==.',
Hp='Hplaysgames:BAAANQADCgYIBgAAAA==.',
Hu='Huneyb:BAAANQADCgYIFQAAAA==.Huneyhunter:BAABNQAECn8dAAIGAAYKHAeYIgD8AAAGAAYKHAeYIgD8AAAAAA==.',
Ic='Ichigozero:BAAANQADCgUIBwAAAA==.',
Ig='Igor:BAAANQADCgEIAQAAAA==.',
Il='Illimommy:BAAANQADCgYIDQAAAA==.',
In='Intern:BAAANQAECgQIDQAAAA==.',
Ir='Ironaxe:BAABNQAECn8vAAIEAAkKAAzidACMAQAEAAkKAAzidACMAQAAAA==.',
It='Itsademon:BAAANQAECgYICgAAAA==.',
Ja='Jaeksoolie:BAABNQAECn8XAAMkAAgKxg/iFgD7AQAkAAgKxg/iFgD7AQAIAAEKAACxOgExAAAAAA==.Jakyro:BAABNQAECn8lAAMLAAgK2gjJLABAAQALAAgK2gjJLABAAQAZAAYK/A7vEgDYAAAAAA==.Javeech:BAABNQAECn8eAAIFAAcKlhqtlwD0AQAFAAcKlhqtlwD0AQAAAA==.Jaws:BAAANQADCgEIAQAAAA==.Jaypark:BAABNQAECn8dAAIUAAkK7BX0HgA5AgAUAAkK7BX0HgA5AgAAAA==.Jayse:BAABNQAECn8ZAAMhAAoKfgmlFABVAQAhAAoKWwmlFABVAQARAAQK8gR2HQGhAAABNQAECgoKJgAIAKAhAA==.',
Jc='Jchaotic:BAAANQAECgEIAgAAAA==.',
Je='Jeezus:BAAANQAECgQIBAABNQAFFAYICgAKAGwVAA==.Jeren:BAAANQADCggIDAAAAA==.Jesophocles:BAAANQADCgUIDQAAAA==.',
Jo='Joru:BAAANQADCgUIBQAAAA==.Jovero:BAABNQAECn8wAAMOAAoKdxhPHgBpAgAOAAoKdxhPHgBpAgABAAEK6RBwXAA5AAAAAA==.',
Ju='Juanda:BAAANQAFFAEIAQAAAA==.Junghee:BAABNQAECn8+AAMTAAoKoyO0BgAsAwATAAoKoyO0BgAsAwAUAAcK9hQeLQCwAQAAAA==.Juudaz:BAACNQAFFH8KAAIKAAYKbBWdEgAtAQAKAAYKbBWdEgAtAQA1AAQKf14ABAoACgrfJFQFACQDAAoACgr2IlQFACQDABoACgorJJkEAB8DABsABwqwFeNCALkBAAAA.',
['Jï']='Jïnx:BAABNQAECn8pAAIIAAkKriFqIQAEAwAIAAkKriFqIQAEAwAAAA==.',
Ka='Kaalhvel:BAAANQAECgYIEAAAAA==.Kaeric:BAAANQADCgQIBAAAAA==.Kai:BAAANQADCgEIAQAAAA==.Kakahna:BAABNQAECn8lAAQCAAgKYBzdSABDAgACAAgKYBzdSABDAgAFAAQKGgvRFgGQAAAMAAEKLQvFXAAsAAAAAA==.Kapkywa:BAABNQAECn8rAAIQAAoKmyH5AgC5AwAQAAoKmyH5AgC5AwABNQAECgkJHgACAHEbAA==.Kasherquon:BAAANQAECgQIDQABNQAECgUICAADAAAAAA==.Katsumyo:BAAANQADCggIGQAAAA==.Kawaiimonsta:BAAANQADCggICAAAAA==.',
Ke='Kellyx:BAAANQAECgMIAwAAAA==.',
Kh='Khazmcknight:BAAANQADCgEIAQAAAA==.',
Ki='Killersmile:BAAANQADCgYIBgAAAA==.Kilra:BAABNQAECn8bAAIIAAcKigTCkgCtAAAIAAcKigTCkgCtAAAAAA==.Kiyara:BAABNQAECn80AAIEAAoKYBT6QQAXAgAEAAoKYBT6QQAXAgAAAA==.Kizaki:BAABNQAECn8VAAIcAAYKyx2eKQD2AQAcAAYKyx2eKQD2AQAAAA==.',
Kn='Knowoone:BAAANQAECgEIAQAAAA==.',
Ko='Kouelwhip:BAAANQADCgYIBgABNQAFFAMICQALAD0dAA==.',
Kr='Krakin:BAAANQADCgEIAQAAAA==.Krelliz:BAABNQAECn8zAAMSAAgK7xKwbADFAQASAAgK7xKwbADFAQAIAAYKIgeRfADfAAAAAA==.Kristiné:BAAANQAECgEIAQAAAA==.Krolly:BAAANQAECgQICQAAAA==.Krystar:BAAANQAECgYIDwAAAA==.',
Ku='Kungfuwho:BAABNQAECn8lAAQTAAoKTgu2IQB5AQATAAoKTgu2IQB5AQAUAAUK/QdbTwC4AAAiAAEKAADbNgAdAAAAAA==.Kunoíchi:BAAANQADCgcIBwABNQAECgYIFQAcAMsdAA==.',
Kw='Kwassass:BAAANQADCgYIBgAAAA==.',
La='Laysee:BAAANQAECgIIAgAAAA==.',
Le='Legendomega:BAAANQAECgMIBAAAAA==.Leksa:BAAANQABCgEIAQAAAA==.Lenaea:BAACNQAFFH8IAAISAAQKgAUREwDrAAASAAQKgAUREwDrAAA1AAQKf0QAAxIACgoBFjZBAFwCABIACgoBFjZBAFwCAAgABgoDD/2AANUAAAAA.',
Li='Liiege:BAAANQAECggIDwABNQAFFAMICQALAD0dAA==.Likeàßoss:BAAANQADCgIIAwAAAA==.Liltotem:BAAANQADCgEIAQABNQAECgkJLQASAD4hAA==.Linlithyr:BAABNQAECn8xAAMMAAoKCRooDgASAgAMAAoKCRooDgASAgAFAAEKAADXpAEAAAABNQAECgoKPgAKAE0aAA==.',
Lo='Lobø:BAABNQAECn8gAAIEAAcKvhI6jADyAQAEAAcKvhI6jADyAQAAAA==.Lowtierscrub:BAAANQAECgUIBwABNQAECgoKGQARAK0QAA==.',
Lu='Luccyy:BAAANQADCgQICwAAAA==.Lunacaris:BAAANQADCgQIBAAAAA==.Lunamoss:BAAANQADCgYIBwAAAA==.Lunatyc:BAABNQAECn8nAAIaAAkKkA2/VwCxAQAaAAkKkA2/VwCxAQAAAA==.Luth:BAAANQADCggICAABNQAECgYIDwADAAAAAA==.Luthex:BAAANQAECgYIDwAAAA==.',
Ly='Lylacy:BAABNQAECn9GAAIJAAoKyw9RSgC/AQAJAAoKyw9RSgC/AQAAAA==.Lynx:BAAANQAECgQIBAABNQADCgMIBAADAAAAAA==.Lyrea:BAAANQADCgEIAwAAAA==.',
Ma='Madscience:BAABNQAECn8lAAIdAAgKJAUeIAFWAQAdAAgKJAUeIAFWAQAAAA==.Magiicae:BAAANQADCgIIBAABNQAFFAMICQALAD0dAA==.Magoliko:BAAANQAECgEIAgAAAA==.Manatee:BAAANQAECgEIAQAAAA==.Marqfourthre:BAAANQADCgEIAQAAAA==.Maygwyn:BAAANQADCggICgAAAA==.',
Me='Meanshami:BAAANQAECgEIAQAAAA==.Meatlovers:BAABNQAECn8rAAIQAAkKWBtdEgBaAgAQAAkKWBtdEgBaAgAAAA==.Medb:BAAANQADCggIDgAAAA==.Melar:BAABNQAECn83AAMhAAoKIBF+CQC/AQAhAAoKIBF+CQC/AQAjAAYKIwrIIwCoAAAAAA==.Meowmeowmew:BAAANQADCgUIBQABNQAECggIKgACAJghAA==.',
Mi='Minjae:BAAANQAECgUIEAABNQAECgoKPAAJAHUXAA==.Misfirë:BAAANQAECgQIDQABNQAECgoKMgAaACIeAA==.',
Mo='Mogwaí:BAABNQAECn8eAAMTAAgK6xAOHgD4AAATAAcKJg4OHgD4AAAUAAIK7QhrUgA2AAAAAA==.Moondemon:BAAANQADCggIJAAAAA==.Morrìgan:BAAANQAECgMIAgAAAA==.Morvane:BAAANQADCgYICwABNQAECgoKMQACAEoPAA==.Movack:BAABNQAECn8XAAIFAAcKwwph3wBcAQAFAAcKwwph3wBcAQAAAA==.Mowri:BAAANQABCgUICQAAAA==.',
Mu='Multicrit:BAAANQADCgIIAgAAAA==.Murderface:BAABNQAECn8hAAMQAAgKQiJOKABiAQAQAAQKzSBOKABiAQAlAAgK0wkERQDeAAAAAA==.',
My='Mytho:BAAANQAECgEIAgAAAA==.Mythunran:BAABNQAECn8tAAIWAAkKIAmwGQB4AQAWAAkKIAmwGQB4AQAAAA==.',
['Mó']='Mó:BAAANQADCgEIAQAAAA==.',
['Mö']='Mörï:BAABNQAECn8aAAIFAAgK+wtqzwB8AQAFAAgK+wtqzwB8AQAAAA==.',
Na='Naethanial:BAAANQAECgYICQAAAA==.Nas:BAAANQAECgQICQAAAA==.Natalina:BAAANQADCgcJCgABNQAECgIIAgADAAAAAA==.Nav:BAAANQAECgEIAQAAAA==.Nax:BAAANQAECgYICQAAAA==.Naz:BAAANQADCgYIEgAAAA==.',
Ne='Nerfhammer:BAACNQAFFH8RAAIFAAUKuRxXDACEAQAFAAUKuRxXDACEAQA1AAQKf0MAAgUACgoZJfEWAGkDAAUACgoZJfEWAGkDAAAA.Nessalove:BAACNQAFFH8dAAIfAAYKPhO+CQDLAQAfAAYKPhO+CQDLAQA1AAQKf0EAAh8ACgrBHDo4AIcCAB8ACgrBHDo4AIcCAAAA.Neutrino:BAAANQAECgYIDgAAAA==.',
Ni='Nicolbowlass:BAABNQAECn8fAAMZAAoKARGsBwDpAQAZAAoKARGsBwDpAQAmAAEKBgjPJQAtAAAAAA==.Nightomen:BAAANQAECgEIAQABNQAECggIIQAQAEIiAA==.Nipao:BAAANQADCgQIBAAAAA==.Nitafart:BAAANQAECgQICAABNQAECgUIDgADAAAAAA==.',
No='Noone:BAABNQAECn88AAMSAAoK7BLXNgAOAgASAAoK7BLXNgAOAgAIAAYKwQmltAApAQAAAA==.Noriel:BAAANQAECgYIDgAAAA==.',
Nz='Nz:BAAANQAECgcICgAAAA==.',
Od='Oddeccentric:BAAANQAECgcIDwABNQAFFAYIFAAjAPcUAA==.',
Og='Ognyal:BAAANQAECggICAAAAA==.',
On='Onemanarmyy:BAAANQADCgIIAgABNQADCgMIAwADAAAAAA==.Onna:BAAANQADCgMIAwAAAA==.',
Oo='Ooblitoon:BAAANQADCgQIBAAAAA==.',
Op='Opali:BAABNQAECn8VAAMMAAYK9hNUMgBOAQAMAAYKPRJUMgBOAQAFAAUKcg8A1ADzAAAAAA==.',
Os='Osanar:BAABNQAFFH8KAAILAAUKZwOiCgAOAQALAAUKZwOiCgAOAQAAAA==.',
Ov='Oven:BAAANQADCgQIAwABNQAECgoKQAAaAPwjAA==.Overburned:BAAANQAECgUIBgAAAA==.Overshoot:BAABNQAECn8kAAIEAAkKcRLpcgCQAQAEAAkKcRLpcgCQAQAAAA==.',
Ox='Oxen:BAAANQADCgUIBgAAAA==.',
Pa='Pallysmoke:BAAANQADCgUIBQAAAA==.Panterion:BAAANQAECgQIBwABNQAECgkJKgAfAJMbAA==.Papimonk:BAAANQAECgQIBwABNQAECgkJIwASAIwcAA==.Parvarti:BAABNQAECn8lAAMYAAYKvwSQRwCpAAAJAAYKcgRU8gDlAAAYAAUKxgGQRwCpAAAAAA==.Pathogenic:BAABNQAECn8WAAIgAAYKWRMEOABlAQAgAAYKWRMEOABlAQAAAA==.Pathologist:BAAANQADCggICAABNQAECggIFgAgAFkTAA==.Pavin:BAAANQAECggICAAAAA==.',
Pe='Peluquin:BAAANQAECgEIAQAAAA==.Persimmoñ:BAAANQADCggJFAAAAA==.',
Ph='Philliesteak:BAAANQAECgEIAQAAAA==.',
Po='Polkadott:BAABNQAECn8gAAMJAAgKeSPLcQALAgAJAAYKKCTLcQALAgAYAAIKHCK9PgDHAAAAAA==.',
Pr='Presidìum:BAABNQAECn8eAAIMAAgKzhFBHgBHAQAMAAgKzhFBHgBHAQAAAA==.Procbiscuit:BAAANQAECgYJDAAAAA==.Prost:BAABNQAECn8nAAINAAkK4xyCBgCYAgANAAkK4xyCBgCYAgAAAA==.Provoked:BAAANQAECgQIBQABNQAECgoKHwASAEcZAA==.',
Ps='Psylocke:BAABNQAECn8uAAIBAAkKRg3XFABtAQABAAkKRg3XFABtAQAAAA==.',
Pu='Pugshammy:BAAANQAECgMIAwAAAA==.Purdy:BAAANQAECggICAAAAA==.',
Py='Pyroblast:BAAANQAECgUIBwABNQAECgkJHAAOAKoTAA==.',
Ra='Raedon:BAAANQADCgQIBAAAAA==.Rah:BAAANQAECgUICAABNQAECgkJKwAKAE0WAA==.Rahuwu:BAAANQAECgMIAwABNQAECgoKPwARAJUmAA==.Raiser:BAAANQADCgEIAQAAAA==.Raveger:BAAANQADCgYIDwABNQAECggIKgACAJghAA==.',
Re='Reladin:BAABNQAECn8kAAIMAAgKUQs5KAD8AAAMAAgKUQs5KAD8AAAAAA==.Relaeha:BAAANQADCgEIAQAAAA==.Rendaelyne:BAAANQADCggIKAAAAA==.Renzr:BAABNQAECn82AAMaAAoKmSBOHADiAgAaAAoKTB5OHADiAgAKAAcKPSNoHgC/AgAAAA==.Resectum:BAAANQADCgUIBQAAAA==.Retpally:BAAANQADCgMIAwAAAA==.Rexas:BAAANQAECgUICAABNQAFFAcIIQAZALsaAA==.',
Ro='Roag:BAABNQAECn8YAAIdAAcKYArn2QDMAAAdAAcKYArn2QDMAAAAAA==.Roley:BAABNQAECn8xAAIQAAoKpw/0HgC2AQAQAAoKpw/0HgC2AQAAAA==.Rowin:BAAANQAECgcIEwAAAA==.',
Ru='Rustedroots:BAAANQADCgUIBQAAAA==.',
Sa='Sacrosanct:BAAANQADCgIIAgAAAA==.Sansara:BAAANQADCgcIDAABNQAECgQIEwADAAAAAA==.Sapphyre:BAAANQABCgQIBgAAAA==.Saristelonio:BAAANQAECgMIAwABNQAECgkJIAAWAOYJAA==.Saristrix:BAABNQAECn8gAAIWAAkK5gliIwAVAQAWAAkK5gliIwAVAQAAAA==.Sarnara:BAABNQAECn8yAAIMAAkK1BpIFQBXAgAMAAkK1BpIFQBXAgAAAA==.Satyria:BAAANQAECgQJBgAAAA==.Savagedeath:BAAANQAECgIIBgAAAA==.Savagelight:BAAANQAECgEIAQABNQAECgIIBgADAAAAAA==.',
Se='Secord:BAABNQAECn8qAAIEAAYK2ALJAAEDAQAEAAYK2ALJAAEDAQAAAA==.Senarx:BAAANQAECgEIAQAAAA==.Seonghwa:BAAANQADCgcIFwAAAA==.Sereniity:BAAANQADCgYIBgABNQAFFAMICQALAD0dAA==.Seriiez:BAAANQAECgEIAgAAAA==.',
Sh='Shadowherc:BAAANQADCgUIBQAAAA==.Shamalicous:BAAANQAECgYICgAAAA==.Shamee:BAAANQADCgEIAQAAAA==.Shamous:BAAANQADCgYIDQAAAA==.Shampooh:BAAANQAECgUIBQAAAA==.Shamway:BAAANQADCgEIAQAAAA==.Shanthe:BAAANQADCgUIBQABNQAECgoKLQABAMkaAA==.Sharku:BAACNQAFFH8IAAIdAAQKgg7DSgCSAAAdAAQKgg7DSgCSAAA1AAQKf0gAAx0ACgrmHT4nAIUCAB0ACgrmHT4nAIUCAA0AAQrHF849AEkAAAAA.Shegothalf:BAAANQAECgUICwAAAA==.Shougo:BAAANQADCgQIBAAAAA==.',
Si='Siannean:BAAANQAECgEIAQAAAA==.Sickem:BAAANQAECgQIBAAAAA==.',
Sk='Skibblé:BAABNQAECn8UAAIYAAYKyAbPKAAzAQAYAAYKyAbPKAAzAQAAAA==.',
Sl='Slickcity:BAAANQADCggICAAAAA==.Slimthick:BAAANQAECgQICAAAAA==.Slimthicka:BAAANQADCggICAAAAA==.',
Sm='Smokeofsteel:BAAANQAECgQIEwAAAA==.',
So='Solari:BAAANQADCgYICgABNQAECgoKNgAaAJkgAA==.',
Sp='Spinji:BAAANQADCgUIBQAAAA==.Spliff:BAAANQADCggIAwAAAA==.',
St='Stabsmcshank:BAABNQAECn8nAAMOAAoKbhBYIwCuAQAOAAoKTQ1YIwCuAQABAAUK6hFZXQBBAQAAAA==.Starbux:BAABNQAECn8kAAMfAAoKyA0xSQDaAQAfAAoKyA0xSQDaAQAgAAQK3QJERQBnAAAAAA==.Steakx:BAABNQAECn89AAIEAAoKpyC9GgAuAwAEAAoKpyC9GgAuAwAAAA==.Stormwulf:BAABNQAECn8gAAMSAAgKJByvQgDYAQASAAgKJByvQgDYAQAIAAIKCwwjuQBoAAAAAA==.',
Su='Sunmae:BAABNQAECn8WAAIIAAgKIQ4udADFAQAIAAgKIQ4udADFAQABNQAECggIIwAGAFATAA==.Suriel:BAAANQAECgQIEwAAAA==.Suumcuique:BAAANQADCggICQABNQAECggIIQAQAEIiAA==.',
Sv='Svaha:BAAANQADCgYIFQABNQAECgkJIAAEALcRAA==.Svenya:BAABNQAECn8aAAMQAAkKKhDoQwANAQAQAAcKeAroQwANAQAlAAMK+AUlowBVAAAAAA==.',
Sy='Sygne:BAAANQAECgUIDwAAAA==.Sylphid:BAABNQAECn8rAAMFAAoKbxOQVQD2AQAFAAoKNhOQVQD2AQAMAAUKbg73LwDMAAABNQAFFAYICgAKAGwVAA==.',
Sz='Szell:BAABNQAECn8oAAIEAAcKLQ4FngAyAQAEAAcKLQ4FngAyAQAAAA==.',
['Së']='Sëkhmët:BAAANQADCgUIBgABNQADCgMIBAADAAAAAA==.',
['Sï']='Sïenna:BAAANQADCgQIBAAAAA==.',
Ta='Tacituss:BAAANQADCgEIAgABNQADCgcIFAADAAAAAA==.Taln:BAAANQADCgUIDAAAAA==.Tassandie:BAABNQAECn8qAAMfAAkKkxvcPwACAgAfAAkKkxvcPwACAgAgAAEKAAB4ZwAAAAAAAA==.Tayebeh:BAAANQADCgYIGAAAAA==.',
Te='Tektoniik:BAAANQADCgYICgABNQAFFAMICQALAD0dAA==.',
Th='Thatguy:BAAANQAECgcIBwABNQAECgoKLQAdAAMjAA==.Thebrownbear:BAAANQAECgMIAwAAAA==.Theebucket:BAAANQAECgcIBwAAAA==.Theo:BAAANQAECggIDQABNQAECgoKMwAfACIaAA==.Therese:BAAANQADCgUIBQAAAA==.Theresee:BAAANQADCggIEAAAAA==.Thorylianna:BAAANQADCgYIBgABNQAECgoKPgAKAE0aAA==.Thurmfald:BAAANQADCgEIAQAAAA==.',
Ti='Tionie:BAAANQAECggIEwAAAA==.',
To='Toiletnuker:BAAANQADCgUJCQABNQAECggIKgACAJghAA==.Tokyojoe:BAACNQAFFH8KAAIcAAQKzAtkCADEAAAcAAQKzAtkCADEAAA1AAQKfzAAAhwACgouFf0eAFgCABwACgouFf0eAFgCAAAA.Torrick:BAAANQAECgcICgABNQAECgkJLAALAGIQAA==.Totemtot:BAABNQAECn8lAAIkAAgK8gMSIgA7AQAkAAgK8gMSIgA7AQAAAA==.Toupee:BAAANQAECgEIAQAAAA==.',
Tr='Tradrivia:BAAANQADCgMIBAABNQAECgkJMwAHAKklAA==.Traelindra:BAAANQADCggIFwAAAA==.Tryxtyflyx:BAAANQAECgEIAQAAAA==.',
Ty='Tydistus:BAAANQADCgMIAwAAAA==.Tygrala:BAAANQADCgYICwABNQAECgkJMgAMANQaAA==.',
Uf='Uffizzle:BAAANQAECggIDwAAAA==.',
Ul='Ulf:BAABNQAECn85AAISAAoKCSEtGAATAwASAAoKCSEtGAATAwAAAA==.',
Un='Unheardssk:BAAANQADCgQIBAABNQAECgUICgADAAAAAA==.Unholycow:BAAANQADCgEIAQAAAA==.',
Va='Valquirie:BAABNQAECn8+AAIKAAoKTRohGAAcAgAKAAoKTRohGAAcAgAAAA==.Varlamor:BAABNQAECn8dAAMgAAcKBAk1OwBPAQAgAAcKBAk1OwBPAQAfAAEKvAPXAwEoAAAAAA==.Varolokiir:BAAANQADCgEIAQABNQAFFAMICQALAD0dAA==.Vathraen:BAAANQADCgYICgAAAA==.',
Ve='Velanistra:BAABNQAECn8iAAIFAAoKSggVoQBKAQAFAAoKSggVoQBKAQAAAA==.Velanya:BAAANQADCgUIBQAAAA==.Velnia:BAAANQAECgMIBAAAAA==.Vervane:BAABNQAECn8vAAIPAAkKLQuJNAA8AQAPAAkKLQuJNAA8AQAAAA==.',
Vg='Vgerr:BAABNQAECn8nAAIFAAgKgQrn6ABKAQAFAAgKgQrn6ABKAQAAAA==.',
Vi='Vidarus:BAAANQADCggICQABNQAFFAUIEQAFALkcAA==.',
Vo='Vohu:BAABNQAECn8uAAMEAAkKVBo1SAAEAgAEAAkKGBo1SAAEAgAWAAcKcxD0OgB5AQAAAA==.Voidpower:BAABNQAECn8XAAIcAAkKbwcpJwAnAQAcAAkKbwcpJwAnAQAAAA==.Vozzle:BAAANQADCgQIDQAAAA==.',
['Và']='Vàlentine:BAAANQADCgQIBAAAAA==.',
Wa='Walane:BAAANQAECgQIBAAAAA==.Warlokee:BAAANQADCgEIAQAAAA==.Waterlily:BAAANQADCgMIBAAAAA==.',
Wi='Wiglet:BAAANQADCgYIBwAAAA==.Windeyaho:BAABNQAECn8cAAIHAAoKySP3BQA0AwAHAAoKySP3BQA0AwAAAA==.',
Xa='Xal:BAAANQAECgQICAABNQAECgoKNwAMAJ8eAA==.Xapwv:BAAANQADCgQIBQAAAA==.',
Xe='Xent:BAAANQAECgcIDQAAAA==.',
Xt='Xten:BAAANQAECgQIEwAAAA==.',
Yo='Yoshinox:BAABNQAECn9LAAIEAAoK1CEjDAB8AwAEAAoK1CEjDAB8AwAAAA==.',
Za='Zalth:BAAANQADCgIIAgAAAA==.',
Ze='Zelliph:BAAANQAECgYIDQAAAA==.Zenagdrina:BAABNQAECn8iAAIEAAgKKghmnQAzAQAEAAgKKghmnQAzAQAAAA==.Zenobiå:BAABNQAECn81AAIIAAkKgA9ARgCCAQAIAAkKgA9ARgCCAQAAAA==.Zeypher:BAAANQADCgcIGgAAAA==.',
Zh='Zhaann:BAAANQAECgQIEwAAAA==.',
Zi='Zinarra:BAAANQADCgcIBwAAAA==.Ziron:BAAANQADCgIIAgABNQAECgUICgADAAAAAA==.Zironlock:BAABNQAECn8VAAIJAAgKiBPjbAAXAgAJAAgKiBPjbAAXAgABNQAECgUICgADAAAAAA==.',
Zo='Zorach:BAAANQAECgIIAgAAAA==.',
Zu='Zugga:BAAANQAECgQIBAABNQAFFAQICgAcAMwLAA==.',
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

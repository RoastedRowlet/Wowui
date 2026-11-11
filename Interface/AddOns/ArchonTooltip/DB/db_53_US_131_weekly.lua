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

local lookup = {'Paladin-Holy','Priest-Shadow','Hunter-BeastMastery','Paladin-Retribution','Unknown-Unknown','Druid-Feral','Druid-Guardian','Shaman-Elemental','Warlock-Demonology','DeathKnight-Blood','Evoker-Preservation','Paladin-Protection','Mage-Frost','Rogue-Subtlety','Rogue-Assassination','DemonHunter-Havoc','Druid-Restoration','Warrior-Arms','Shaman-Restoration','Monk-Mistweaver','Monk-Windwalker','Mage-Arcane','Hunter-Survival','Hunter-Marksmanship','Warlock-Affliction','Warlock-Destruction','Evoker-Devastation','DeathKnight-Unholy','DeathKnight-Frost','DemonHunter-Devourer','DemonHunter-Vengeance','Priest-Holy','Warrior-Fury','Warrior-Protection','Monk-Brewmaster','Shaman-Enhancement','Druid-Balance','Evoker-Augmentation',}
local provider = {region='US',realm='KhazModan',name='US',type='weekly',zone=53,date='2026-11-10',data={Ad='Advîl:BAABNQAECn8tAAIBAAoKDR1zGADjAgABAAoKDR1zGADjAgAAAA==.',
Ae='Aeryhnn:BAAANQADCgcIHwABNQAECgYIGQACACcIAA==.',
Al='Alarogue:BAAANQAECgcIDQAAAA==.Alexandre:BAABNQAECn8mAAIDAAoKMxH+fgChAQADAAoKMxH+fgChAQAAAA==.Allasia:BAAANQAECgUIBwAAAA==.Alterboy:BAAANQADCgIIAgABNQAECgkJLQABABoiAA==.Alton:BAABNQAECn8xAAIBAAoKSg9hWAAQAgABAAoKSg9hWAAQAgAAAA==.',
Am='Amoonsia:BAAANQAECgQIBgAAAA==.',
An='Anfernyphere:BAABNQAECn8VAAMBAAgKyx7VLQCvAgABAAgKyx7VLQCvAgAEAAQK8w/PHwHqAAABNQAECgQIBQAFAAAAAA==.Ansuz:BAAANQAECgIIAQAAAA==.Anvil:BAAANQADCgMIAwAAAA==.',
Ap='Aphroditee:BAAANQADCgUIBQAAAA==.Apostriss:BAAANQADCgMIAwAAAA==.',
Aq='Aquafresh:BAAANQADCgUJBQAAAA==.',
Ar='Arisel:BAABNQAECn8mAAMGAAkKahQXEACmAQAGAAkKahQXEACmAQAHAAYKRwtGMwAHAQAAAA==.Aristia:BAAANQADCggIDgABNQAFFAIICAAIAC0EAA==.Arweni:BAAANQAECgIIAQAAAA==.',
At='Atheizt:BAABNQAECn8eAAIBAAkKcRtgJwDLAgABAAkKcRtgJwDLAgAAAA==.',
Az='Azael:BAAANQADCgcIEAAAAA==.',
Ba='Badned:BAAANQAECggICAAAAA==.Bakachan:BAAANQAECgIIAgAAAA==.Baldilocks:BAAANQADCgQIBAAAAA==.Banedon:BAAANQADCgMJBQABNQAECgkJLQABABoiAA==.',
Be='Bearbacked:BAAANQADCgYIBgABNQAECgUIDgAFAAAAAA==.Beastmaster:BAAANQAECgMIAwAAAA==.Beetingu:BAAANQADCgcIFgABNQAECggIIAAJAHkjAA==.Belashar:BAAANQADCgYIGAAAAA==.Beytuha:BAABNQAECn85AAIHAAoKxyUoAgBZAwAHAAoKxyUoAgBZAwAAAA==.',
Bi='Bighornygay:BAAANQAECggIBQAAAA==.Bigsmoke:BAAANQADCgUIBQAAAA==.',
Bl='Blacken:BAABNQAECn8gAAIKAAcK6xknPQA9AQAKAAcK6xknPQA9AQAAAA==.Blackknife:BAAANQADCgQIBAAAAA==.Bladestorm:BAAANQAECgYICQABNQAFFAMICQALAD0dAA==.Blakylightz:BAABNQAECn8bAAMEAAkKwhrYXgAFAgAEAAgKRhnYXgAFAgAMAAQKqh3bIQBJAQABNQAFFAIIBAAFAAAAAA==.Blazen:BAABNQAECn8sAAIIAAoKESB/IAAJAwAIAAoKESB/IAAJAwAAAA==.Blinker:BAABNQAECn8iAAINAAkKXguxDwB3AQANAAkKXguxDwB3AQAAAA==.Bloodynuts:BAABNQAECn8cAAMOAAkKqhOAFwAiAgAOAAgKURSAFwAiAgAPAAIKzhImjwB1AAAAAA==.Bloyfbloyf:BAACNQAFFH8HAAIQAAQKzgTwEQCaAAAQAAQKzgTwEQCaAAA1AAQKfywAAhAACgoBGfAWAE8CABAACgoBGfAWAE8CAAAA.Blueberriess:BAAANQAECgQIBAAAAA==.Blueshadøw:BAAANQADCgcIBwAAAA==.',
Bo='Bobbidyboo:BAACNQAFFH8ZAAIRAAYKNwZnBwBcAQARAAYKNwZnBwBcAQA1AAQKf0IAAhEACgoVE+4kAPwBABEACgoVE+4kAPwBAAAA.Bocknot:BAAANQAECgEIAQAAAA==.Bonesclone:BAAANQAECgMIAgAAAA==.',
Br='Brewshido:BAAANQAECgMIBQAAAA==.Briareosx:BAABNQAECn85AAISAAoKDxz8SACvAgASAAoKDxz8SACvAgAAAA==.Brixtia:BAAANQADCgcIBgABNQAECgoKNAADAJsbAA==.Brovar:BAACNQAFFH8bAAIEAAYKch0qBwBhAQAEAAYKch0qBwBhAQA1AAQKf0IAAgQACgpHJDIWAGwDAAQACgpHJDIWAGwDAAAA.',
Bu='Bubbaa:BAABNQAECn8hAAMTAAkKrR/+IQDgAgATAAkKrR/+IQDgAgAIAAEKAAAMJAFJAAAAAA==.Buddydaelf:BAABNQAECn8lAAIDAAoKDBbKXwBXAgADAAoKDBbKXwBXAgAAAA==.',
Bw='Bwonsamdî:BAAANQAECgIIAwAAAA==.Bwonshlongdi:BAAANQADCgYIBgAAAA==.',
Ca='Cathexis:BAAANQADCggIEAABNQAECgoKMAALALAPAA==.',
Ce='Ceanaflowers:BAABNQAECn8ZAAISAAoKrRBwjAD9AQASAAoKrRBwjAD9AQAAAA==.',
Ch='Challah:BAAANQAECgMIBAAAAA==.Chia:BAABNQAECn8wAAMUAAoKFRbkDQArAgAUAAoKFRbkDQArAgAVAAIKnQaEYQBZAAABNQADCgMIAwAFAAAAAA==.Chianamoya:BAAANQADCgcIEgABNQAECgYIGQAKAJIJAA==.Chune:BAAANQADCgQIBAAAAA==.',
Cl='Clarisse:BAAANQAECgMIAQABNQAECgoKQAAKAGsaAA==.',
Co='Coldburn:BAAANQADCgQIBAAAAA==.Connor:BAAANQAECgQICQAAAA==.Coolarrow:BAABNQAECn8tAAIDAAkKPxssLwB4AgADAAkKPxssLwB4AgABNQAFFAQIFgADAB4fAA==.Cosby:BAAANQADCgEIAQAAAA==.',
Cr='Cracken:BAAANQABCgYIBgAAAA==.Croissantx:BAABNQAECn8YAAIWAAcKJA+IswAsAQAWAAcKJA+IswAsAQAAAA==.Crosshair:BAABNQAECn8fAAMXAAcKTxNvCABYAQAXAAcKTxNvCABYAQAYAAEKXAHingAfAAAAAA==.',
Cu='Cutpo:BAAANQAECgQIBAABNQAFFAcIFQAJAMIQAA==.',
Cy='Cyndrenissa:BAAANQADCgEIAQAAAA==.Cynris:BAAANQAECgEIAQABNQAECgoKQAAMAGwgAA==.',
['Cê']='Cêlaçane:BAAANQADCgIJAgAAAA==.',
Da='Dacianstorm:BAAANQADCgIIAgAAAA==.Dacianwolf:BAAANQAECggICwAAAA==.Dagaz:BAAANQADCgUIBQAAAA==.Daravinius:BAAANQAECgYIDgAAAA==.Dare:BAAANQAECgQJBwAAAA==.Davaeh:BAAANQADCgIIAgABNQAECgkJLQABABoiAA==.Davandar:BAAANQADCgYIDAAAAA==.Daveah:BAABNQAECn8sAAITAAkK/wilbgBRAQATAAkK/wilbgBRAQAAAA==.',
De='Deathberry:BAABNQAECn8zAAIJAAgKYQ1ukAC9AQAJAAgKYQ1ukAC9AQAAAA==.Deathsmoke:BAAANQADCgEIAQAAAA==.Delphron:BAAANQAECgIIAgAAAA==.Demoncharge:BAAANQAECgEIAgAAAA==.Demonflayer:BAAANQAECgEIAQABNQAECgEIAgAFAAAAAA==.Demonlust:BAAANQAECgEIAQABNQAECgEIAgAFAAAAAA==.Denaeaa:BAABNQAECn8YAAMUAAcKYBeXGQDmAQAUAAcKYBeXGQDmAQAVAAIKlgBSXwAjAAABNQAFFAQICAATAIAFAA==.Depala:BAAANQADCgcIEAABNQAECgIIAgAFAAAAAA==.Devilzkry:BAAANQADCgUIBQAAAA==.Devistaysha:BAABNQAECn88AAMIAAoK8RNiNADvAQAIAAoK8RNiNADvAQATAAEKvgEfAwEhAAAAAA==.',
Dh='Dharmakat:BAAANQADCgUICQAAAA==.',
Di='Dist:BAAANQAECgMICQAAAA==.Divinestorm:BAABNQAECn8tAAMBAAkKGiIeGgDXAgABAAgKmCEeGgDXAgAEAAgKoA3kuABJAQAAAA==.Divinethis:BAAANQADCgIIAgAAAA==.',
Dn='Dnyal:BAAANQAECggIEAAAAA==.',
Do='Dodgysenpai:BAAANQADCgUIBQABNQAECgoKPwASAJUmAA==.Dogbreathrlz:BAAANQABCgUIBwAAAA==.Dolomite:BAAANQAECgIIBgAAAA==.Dookerslol:BAAANQADCgUIAwAAAA==.Dotexe:BAABNQAECn8vAAIPAAgKXx2LDAD1AQAPAAgKXx2LDAD1AQAAAA==.Dotsy:BAACNQAFFH8eAAQZAAcKKRsLAQBjAQAZAAYK8R0LAQBjAQAJAAUKJhqAEwD1AAAaAAEKlxOOGgBQAAA1AAQKf0UABBoACgqjIVgTANcBAAkACQrPIJUzALsCABoABgoXH1gTANcBABkABwqUHn0MAFwBAAAA.',
Dr='Drackarys:BAAANQADCgcIIgAAAA==.Dragooner:BAAANQADCgMIAwAAAA==.Drakiir:BAACNQAFFH8JAAMLAAMKPR1xDQDwAAALAAMKPR1xDQDwAAAbAAIKCSMGBACyAAA1AAQKf0AAAwsACgqxIU4DAIMDAAsACgqxIU4DAIMDABsACAqpIH4PAGICAAAA.Dralkish:BAAANQAECgEIAQAAAA==.Drathi:BAABNQAECn8wAAMLAAoKsA8tIgC6AQALAAoKsA8tIgC6AQAbAAcKcw2QIQBCAQAAAA==.Dravas:BAAANQAECgUICgAAAA==.Draxis:BAAANQADCggIDgAAAA==.Drezzo:BAAANQADCgcIFgAAAA==.Dryerbro:BAAANQABCgUIBQAAAA==.Drzark:BAABNQAECn8VAAINAAYKFgcQHADfAAANAAYKFgcQHADfAAAAAA==.',
Du='Duskwulf:BAAANQADCgMIBQABNQAECggIIgATACQcAA==.',
Dw='Dwdog:BAABNQAECn8jAAIZAAkKfQ/WBwDQAQAZAAkKfQ/WBwDQAQAAAA==.',
['Dà']='Dàthguy:BAABNQAECn9BAAIcAAoK/iRpAwC+AwAcAAoK/iRpAwC+AwAAAA==.',
['Dé']='Défault:BAABNQAECn8yAAMcAAoKIh4wEwAfAwAcAAoKIh4wEwAfAwAdAAQKOA0hcwDTAAAAAA==.',
Ed='Edaras:BAAANQAECgIIAwAAAA==.',
Ef='Effrøn:BAAANQAECgUIBQAAAA==.',
El='Elek:BAAANQAECgYICwABNQAFFAUIBwAaAIsRAA==.Elennie:BAAANQAECgIIAgAAAA==.Elista:BAAANQABCgcICAAAAA==.',
Em='Emmi:BAABNQAECn8gAAIcAAgKfRfpJwCPAQAcAAgKfRfpJwCPAQAAAA==.',
En='Enyo:BAABNQAECn8oAAIeAAkKQRQnJgAUAgAeAAkKQRQnJgAUAgAAAA==.',
Er='Erad:BAAANQADCgcIDAAAAA==.',
Ev='Evilritê:BAAANQADCggIEQAAAA==.Evilspawn:BAAANQADCgQIBAAAAA==.',
Ex='Excalipoor:BAAANQADCgEIAgAAAA==.',
Fa='Faloran:BAAANQAECgIIAQAAAA==.Farstad:BAAANQADCgUIBQAAAA==.Fayereadmore:BAAANQADCggICgAAAA==.',
Fe='Fearmyhunter:BAAANQADCggJCQAAAA==.Fekk:BAAANQADCggIDgABNQAECggIDwAFAAAAAA==.Felsmoke:BAAANQADCgYIBgAAAA==.Fervid:BAABNQAECn8pAAIWAAgKABPangBUAQAWAAgKABPangBUAQAAAA==.Feylen:BAABNQAECn8yAAIWAAoK4SUkCgCvAwAWAAoK4SUkCgCvAwAAAA==.',
Fi='Fido:BAABNQAECn8qAAIKAAkKnQ82OQBQAQAKAAkKnQ82OQBQAQAAAA==.Fidø:BAAANQADCgUIDwABNQAECgkJKgAKAJ0PAA==.Fifthelement:BAABNQAECn8zAAITAAoKtSBFDwAzAwATAAoKtSBFDwAzAwAAAA==.Figgson:BAAANQADCgQIBAAAAA==.Figgy:BAABNQAECn8lAAITAAgK7hYiWgCWAQATAAgK7hYiWgCWAQAAAA==.Fiorstrasza:BAABNQAECn8tAAMLAAoK+hPoDgAIAgALAAoK+hPoDgAIAgAbAAIKbwZNNgBcAAAAAA==.Firry:BAAANQADCgYIEgAAAA==.Fistsofsmoke:BAAANQADCgUICAAAAA==.',
Fj='Fjalgeirr:BAABNQAECn85AAMQAAoKxRChJQDIAQAQAAoKxRChJQDIAQAfAAEKAADSPQAFAAAAAA==.',
Fl='Flockling:BAAANQADCggIDQAAAA==.',
Fo='Foxymomma:BAABNQAECn8lAAIgAAgKmBisTQDsAQAgAAgKmBisTQDsAQAAAA==.',
Fr='Freaksbetter:BAAANQADCgcIBwAAAA==.Froot:BAAANQAECgUIDgAAAA==.Frßlizzard:BAAANQAECgEIAQAAAA==.Frìga:BAAANQADCgUIBQAAAA==.',
Fu='Fulgar:BAABNQAECn8+AAIEAAoKHSDGLgAOAwAEAAoKHSDGLgAOAwAAAA==.',
Ga='Galatea:BAAANQAECgUIBQAAAA==.Gaëll:BAAANQAECgEIAQAAAA==.',
Ge='Gearsprocket:BAABNQAECn8bAAQhAAoKlRGVDADyAQAhAAcKoBeVDADyAQAiAAMK0gagLgB8AAASAAIKlgWNHAE5AAABNQAECgoKMQABAEoPAA==.Geosmin:BAABNQAECn8bAAITAAkKsBAuYwDkAQATAAkKsBAuYwDkAQAAAA==.Geronimoose:BAAANQADCgYJDAABNQAECgoKMQABAEoPAA==.',
Gh='Ghue:BAABNQAECn8dAAMMAAoKngqLIQBLAQAMAAoK5wiLIQBLAQAEAAYKMwzQAgEbAQAAAA==.Ghòst:BAAANQAECgMIAgAAAA==.',
Gi='Gilalade:BAABNQAECn8gAAIDAAgKBxYHjQDwAQADAAgKBxYHjQDwAQAAAA==.Girlboss:BAAANQADCgQIBAAAAA==.',
Gl='Glissa:BAAANQAECgIIAgABNQAECgoKKwAbAEcYAA==.',
Go='Gobann:BAAANQAECgUIBQABNQAECgoKNAADAJsbAA==.Gonern:BAABNQAECn9AAAMMAAoKbCDQCgDuAgAMAAoKJB7QCgDuAgAEAAkKvByIbgDfAQAAAA==.Gooby:BAACNQAFFH8SAAIgAAUKdxY5EACSAQAgAAUKdxY5EACSAQA1AAQKfxwAAyAACgqYGVwzAF0CACAACgqYGVwzAF0CAAIAAQrvAImTABUAAAAA.Goond:BAAANQAECgcIDQABNQAFFAUIBwAaAIsRAA==.Gooney:BAAANQAECgQIBgAAAA==.Gotwood:BAAANQADCgYIBgAAAA==.',
Gr='Gravestorm:BAAANQABCggIIQAAAA==.Grimes:BAAANQADCgcIBwABNQAECgUIDgAFAAAAAA==.Grlfriend:BAAANQAECgUIDAAAAA==.Grodin:BAAANQAECgUIBQAAAA==.Grofiest:BAABNQAECn8tAAMCAAoKARD2FwDQAQACAAoKARD2FwDQAQAgAAEKoAFD+QAbAAAAAA==.',
Gu='Gugg:BAAANQADCgIJAgABNQAECgoKPwASAJUmAA==.Guggychan:BAABNQAECn8/AAMSAAoKlSbpAgDkAwASAAoKdSbpAgDkAwAhAAMKTSZuGQDWAAAAAA==.Guggys:BAAANQAECgQIBAAAAA==.Gunslinger:BAAANQAECggIDwAAAA==.Gunsmoke:BAAANQAECgEIAQAAAA==.',
Gw='Gwynbleidd:BAABNQAECn9FAAIKAAoK0RAYLACWAQAKAAoK0RAYLACWAQAAAA==.',
Ha='Hadrian:BAAANQADCgYIDwAAAA==.Haldor:BAAANQADCgcIBwAAAA==.Hanohakua:BAAANQADCgcIDgAAAA==.Haohmaru:BAABNQAECn8lAAIjAAgKwxw9CgByAgAjAAgKwxw9CgByAgAAAA==.Harthen:BAAANQADCgcIGAABNQAECgkJJgAGAGoUAA==.Hashbrowns:BAAANQADCgIIAgAAAA==.',
He='Hellßoy:BAAANQADCgUICwAAAA==.Herc:BAAANQAECgIIAgAAAA==.Hercgrim:BAABNQAECn8WAAQhAAcKHhQEGQARAQASAAYK2xBL4AApAQAhAAQKOhsEGQARAQAiAAEK8gyJRwAmAAAAAA==.Hercsham:BAAANQAECgIIAgAAAA==.Herger:BAAANQABCgYICgAAAA==.',
Hi='Hipsta:BAABNQAECn8gAAIEAAoK7gnU1QBwAQAEAAoK7gnU1QBwAQAAAA==.',
Ho='Hollowshkari:BAAANQADCgYICAAAAA==.Holyclunge:BAAANQAECggICwAAAA==.Holypower:BAAANQADCgcIBwAAAA==.Horexion:BAAANQADCgUJBQAAAA==.',
Hp='Hplaysgames:BAAANQADCgYIBgAAAA==.',
Hu='Huneyb:BAAANQADCgYIEgAAAA==.Huneyhunter:BAABNQAECn8dAAIGAAYKHAeYIgD8AAAGAAYKHAeYIgD8AAAAAA==.',
Ic='Ichigozero:BAAANQADCgUIBwAAAA==.',
Ig='Igor:BAAANQABCgQIAgAAAA==.',
Il='Illimommy:BAAANQADCgYICwAAAA==.',
In='Intern:BAAANQAECgYIDQAAAA==.',
Ir='Ironaxe:BAABNQAECn8zAAIDAAoKpAw1aQDXAQADAAoKpAw1aQDXAQAAAA==.',
It='Itsademon:BAAANQAECgcICwAAAA==.',
Ja='Jaeksoolie:BAABNQAECn8XAAMkAAgKxg/iFgD7AQAkAAgKxg/iFgD7AQAIAAEKAACxOgExAAAAAA==.Jakyro:BAABNQAECn8lAAMLAAgK2gjJLABAAQALAAgK2gjJLABAAQAbAAYK/A7WFADWAAAAAA==.Javeech:BAABNQAECn8eAAIEAAcKlhqtlwD0AQAEAAcKlhqtlwD0AQAAAA==.Jaypark:BAABNQAECn8dAAIVAAkK7BX0HgA5AgAVAAkK7BX0HgA5AgAAAA==.Jayse:BAABNQAECn8ZAAMhAAoKfgmlFABVAQAhAAoKWwmlFABVAQASAAQK8gR2HQGhAAABNQAECgoKJgAIAKAhAA==.',
Jc='Jchaotic:BAAANQADCgUICAAAAA==.',
Je='Jeezus:BAAANQAECgQIBAABNQAFFAYICgAKAGwVAA==.Jeren:BAAANQADCggIDAAAAA==.Jesophocles:BAAANQADCgUIDAAAAA==.',
Jo='Joru:BAAANQADCgUIBQAAAA==.Jovero:BAABNQAECn82AAMOAAoKSBlRIQB2AgAOAAoKSBlRIQB2AgAPAAEK6RDRXwA5AAAAAA==.',
Ju='Juanda:BAABNQAECn8YAAIIAAcKLCGlKAAtAgAIAAcKLCGlKAAtAgAAAA==.Junghee:BAABNQAECn9EAAMUAAoKoyPKBABRAwAUAAoKoyPKBABRAwAVAAcK9hQeLQCwAQAAAA==.Juudaz:BAACNQAFFH8KAAIKAAYKbBWdEgAtAQAKAAYKbBWdEgAtAQA1AAQKf3AABAoACgrfJAwEAEEDAAoACgrwIwwEAEEDABwACgorJLoFABMDAB0ACAoCFuNCALkBAAAA.',
['Jï']='Jïnx:BAABNQAECn8wAAIIAAoKzyIcEADiAgAIAAoKzyIcEADiAgAAAA==.',
Ka='Kaalhvel:BAAANQAECgYIEAAAAA==.Kaeric:BAAANQADCgQIBAAAAA==.Kakahna:BAABNQAECn8lAAQBAAgKYBzdSABDAgABAAgKYBzdSABDAgAEAAQKGgtSMgGNAAAMAAEKLQsYZQArAAAAAA==.Kapkywa:BAABNQAECn8xAAIRAAoK3iJTAgDnAwARAAoK3iJTAgDnAwABNQAECgkJHgABAHEbAA==.Kasherquon:BAAANQAECgQIDAABNQAECgUICAAFAAAAAA==.Katsumyo:BAAANQADCggIGgAAAA==.Kawaiimonsta:BAAANQADCggICQAAAA==.',
Ke='Kellyx:BAAANQAECgMIAwAAAA==.',
Kh='Khazmcknight:BAAANQADCgEIAQAAAA==.',
Ki='Killersmile:BAAANQADCgYIBgAAAA==.Kilra:BAABNQAECn8fAAIIAAcKjATEnQC3AAAIAAcKjATEnQC3AAAAAA==.Kiyara:BAABNQAECn84AAIDAAoKQhXPRwAuAgADAAoKQhXPRwAuAgAAAA==.Kizaki:BAABNQAECn8VAAIeAAYKyx2eKQD2AQAeAAYKyx2eKQD2AQAAAA==.',
Kn='Knowoone:BAAANQAECgEIAQAAAA==.',
Ko='Kouelwhip:BAAANQADCgYIBgABNQAFFAMICQALAD0dAA==.',
Kr='Krelliz:BAABNQAECn8zAAMTAAgK7xKwbADFAQATAAgK7xKwbADFAQAIAAYKIgckiwDfAAAAAA==.Krolly:BAAANQAECgQICQAAAA==.Krystar:BAAANQAECgYIDwAAAA==.',
Ku='Kungfuwho:BAABNQAECn8lAAQUAAoKTgu2IQB5AQAUAAoKTgu2IQB5AQAVAAUK/QdbTwC4AAAjAAEKAADbNgAdAAAAAA==.Kunoíchi:BAAANQADCgcIBwABNQAECgYIFQAeAMsdAA==.',
Kw='Kwassass:BAAANQADCgYIBgAAAA==.',
La='Laysee:BAAANQAECgIIAgAAAA==.',
Le='Legendomega:BAAANQAECgMIAwAAAA==.Leksa:BAAANQABCgEIAQAAAA==.Lenaea:BAACNQAFFH8IAAITAAQKgAUNFgDrAAATAAQKgAUNFgDrAAA1AAQKf0UAAxMACgoBFjZBAFwCABMACgoBFjZBAFwCAAgABgoDD7yPANUAAAAA.',
Li='Liiege:BAAANQAECggIDwABNQAFFAMICQALAD0dAA==.Likeàßoss:BAAANQADCgIIAgAAAA==.Linlithyr:BAABNQAECn85AAMMAAoKuxprDwAeAgAMAAoKuxprDwAeAgAEAAEKAAADwQEAAAABNQAECgoKQAAKAGsaAA==.',
Lo='Lobø:BAABNQAECn8mAAIDAAkKBBI6jADyAQADAAkKBBI6jADyAQAAAA==.Lowtierscrub:BAAANQAECgUIBwABNQAECgoKGQASAK0QAA==.',
Lu='Luccyy:BAAANQADCgQICwAAAA==.Lunacaris:BAAANQADCgQIBAAAAA==.Lunamoss:BAAANQADCgYIBgAAAA==.Lunatyc:BAABNQAECn8wAAIcAAoKig5PJQCiAQAcAAoKig5PJQCiAQAAAA==.Luth:BAAANQADCggICAABNQAECgYIDwAFAAAAAA==.Luthex:BAAANQAECgYIDwAAAA==.',
Ly='Lylacy:BAABNQAECn9JAAIJAAoKdhAsUQDNAQAJAAoKdhAsUQDNAQAAAA==.Lynx:BAAANQAECgUICQABNQADCgMIAwAFAAAAAA==.Lyrea:BAAANQABCgEIAQAAAA==.',
Ma='Madscience:BAABNQAECn8lAAIWAAgKJAUeIAFWAQAWAAgKJAUeIAFWAQAAAA==.Magiicae:BAAANQADCgIIAgABNQAFFAMICQALAD0dAA==.Magoliko:BAAANQAECgEIAgAAAA==.Marqfourthre:BAAANQABCgYIBwAAAA==.Maygwyn:BAAANQADCggICgAAAA==.',
Me='Meanshami:BAAANQAECgEIAQAAAA==.Meatlovers:BAABNQAECn8rAAIRAAkKWBuzFQBaAgARAAkKWBuzFQBaAgAAAA==.Medb:BAAANQADCggIDQAAAA==.Medy:BAAANQAECggICAAAAA==.Melar:BAABNQAECn89AAMhAAoK1BFgCgDTAQAhAAoK1BFgCgDTAQAiAAYKIwrCKACiAAAAAA==.Meowmeowmew:BAAANQADCgUIBQABNQAECgkJLQABABoiAA==.',
Mi='Minjae:BAAANQAECgYIEgABNQAECgoKRAAJAHUXAA==.Misfirë:BAAANQAECgQIDQABNQAECgoKMgAcACIeAA==.',
Mo='Mogwaí:BAABNQAECn8hAAMUAAkKfAysGwA3AQAUAAkKfAysGwA3AQAVAAIK7QiCWAA2AAAAAA==.Moondemon:BAAANQADCggIHwAAAA==.Morrìgan:BAAANQAECgMIAgAAAA==.Morvane:BAAANQADCgYICQABNQAECgoKMQABAEoPAA==.Movack:BAABNQAECn8ZAAIEAAgKwQph3wBcAQAEAAgKwQph3wBcAQAAAA==.Mowri:BAAANQABCgUICQAAAA==.',
Mu='Multicrit:BAAANQADCgIIAgAAAA==.Murderface:BAABNQAECn8hAAMRAAgKQiKhLgBeAQARAAQKzSChLgBeAQAlAAgK0wnQXgBVAQAAAA==.',
My='Mythunran:BAABNQAECn82AAIYAAoKmgmGGACyAQAYAAoKmgmGGACyAQAAAA==.',
['Mö']='Mörï:BAABNQAECn8aAAIEAAgK+wtqzwB8AQAEAAgK+wtqzwB8AQAAAA==.',
Na='Naethanial:BAAANQAECgYICQAAAA==.Nas:BAAANQAECgQICQAAAA==.Natalina:BAAANQADCgcJCgABNQAECgIIAgAFAAAAAA==.Nav:BAAANQADCgYIDAAAAA==.Nax:BAAANQAECgYICwAAAA==.Naz:BAAANQADCgYIEQAAAA==.',
Ne='Nerfhammer:BAACNQAFFH8RAAIEAAUKuRxXDACEAQAEAAUKuRxXDACEAQA1AAQKf0QAAgQACgoZJfEWAGkDAAQACgoZJfEWAGkDAAAA.Nessalove:BAACNQAFFH8dAAIgAAYKPhOODADCAQAgAAYKPhOODADCAQA1AAQKf0UAAiAACgrBHDo4AIcCACAACgrBHDo4AIcCAAAA.Neutrino:BAAANQAECgYIDgAAAA==.',
Ni='Nicolbowlass:BAABNQAECn8fAAMbAAoKARGmCADmAQAbAAoKARGmCADmAQAmAAEKBgjPJQAtAAAAAA==.Nightomen:BAAANQADCggICAABNQAECggIIQARAEIiAA==.Nipao:BAAANQADCgQIBAAAAA==.Nitafart:BAAANQAECgQICAABNQAECgUIDgAFAAAAAA==.',
No='Noone:BAABNQAECn9AAAMTAAoKdhOEPAAOAgATAAoKdhOEPAAOAgAIAAYKwQmltAApAQAAAA==.Noriel:BAAANQAECgYIDQAAAA==.',
Nz='Nz:BAAANQAECgYICwAAAA==.',
Od='Oddeccentric:BAAANQAECgYIDQABNQAFFAcIFAAbAB8OAA==.',
Og='Ognyal:BAAANQAECggICAAAAA==.',
On='Onemanarmyy:BAAANQADCgIIAgABNQADCgMIAwAFAAAAAA==.Onna:BAAANQADCgMIAwAAAA==.',
Oo='Ooblitoon:BAAANQAECggICAAAAA==.',
Op='Opali:BAABNQAECn8bAAMMAAcKTxNUMgBOAQAMAAYKPRJUMgBOAQAEAAYKYhAhwgA5AQAAAA==.',
Os='Osanar:BAABNQAFFH8PAAILAAYKGgOWCgBBAQALAAYKGgOWCgBBAQAAAA==.',
Ov='Oven:BAAANQADCgQIAwABNQAECgoKQQAcAP4kAA==.Overburned:BAAANQAECgUIBQAAAA==.Overshoot:BAABNQAECn8qAAIDAAoKTxOaYgDoAQADAAoKTxOaYgDoAQAAAA==.',
Ox='Oxen:BAAANQADCgUIBQAAAA==.',
Pa='Pallysmoke:BAAANQADCgUIBQAAAA==.Panterion:BAAANQAECgQIBgABNQAECgoKMAAgAB0cAA==.Papimonk:BAAANQAECgQIBwABNQAECgkJIwATAIwcAA==.Parvarti:BAABNQAECn8lAAMaAAYKvwSQRwCpAAAJAAYKcgRU8gDlAAAaAAUKxgGQRwCpAAAAAA==.Pathogenic:BAABNQAECn8WAAICAAYKWRMEOABlAQACAAYKWRMEOABlAQAAAA==.Pathologist:BAAANQADCggICAABNQAECggIFgACAFkTAA==.Pavin:BAAANQAECggICAAAAA==.',
Pe='Peluquin:BAAANQADCgIIAgAAAA==.Persimmoñ:BAAANQADCggJEgAAAA==.',
Po='Pokeranger:BAAANQADCgEIAQAAAA==.Polkadott:BAABNQAECn8gAAMJAAgKeSPLcQALAgAJAAYKKCTLcQALAgAaAAIKHCK9PgDHAAAAAA==.',
Pr='Presidìum:BAABNQAECn8eAAIMAAgKzhF+IwA9AQAMAAgKzhF+IwA9AQAAAA==.Procbiscuit:BAAANQAECgYJDAAAAA==.Prost:BAABNQAECn8rAAINAAoKJx4FBQB8AgANAAoKJx4FBQB8AgAAAA==.Provoked:BAAANQAECgQIBQABNQAECgoKJgATAGIbAA==.',
Ps='Psylocke:BAABNQAECn8uAAIPAAkKRg2kFgBqAQAPAAkKRg2kFgBqAQAAAA==.',
Pu='Pugshammy:BAAANQAECgMIAwAAAA==.Purdy:BAAANQAECggICAAAAA==.',
Py='Pyroblast:BAAANQAECgUIBwABNQAECgkJHAAOAKoTAA==.',
Ra='Raedon:BAAANQAECgQIBAAAAA==.Rah:BAAANQAECgUICAABNQAECgoKLQAKAFkWAA==.Rahuwu:BAAANQAECgMIAwABNQAECgoKPwASAJUmAA==.Raveger:BAAANQADCgYIDwABNQAECgkJLQABABoiAA==.',
Re='Reladin:BAABNQAECn8kAAIMAAgKUQsFLgDzAAAMAAgKUQsFLgDzAAAAAA==.Relaeha:BAAANQADCgEIAQAAAA==.Rendaelyne:BAAANQADCggIKAAAAA==.Renzr:BAABNQAECn85AAMcAAoK8CJOHADiAgAcAAoKzSBOHADiAgAKAAcKPSNoHgC/AgAAAA==.Resectum:BAAANQADCgUIBQAAAA==.Retpally:BAAANQADCgMIAwAAAA==.Rexas:BAAANQAECgUICAABNQAFFAgIIwAbAIcbAA==.',
Ro='Roag:BAABNQAECn8YAAIWAAcKYAox6QDJAAAWAAcKYAox6QDJAAAAAA==.Roley:BAABNQAECn81AAIRAAoKIRDjIQDMAQARAAoKIRDjIQDMAQAAAA==.Rowin:BAAANQAECgcIEwAAAA==.',
Ru='Rustedroots:BAAANQADCgUIBQAAAA==.',
Sa='Sacrosanct:BAAANQADCgIIAgAAAA==.Sansara:BAAANQADCgcIDAABNQAECgYIGQAKAJIJAA==.Sapphyre:BAAANQABCgQIBgAAAA==.Saristelonio:BAAANQAECgMIAwABNQAECgkJIgAYAOYJAA==.Saristrix:BAABNQAECn8iAAIYAAkK5gkDJwAeAQAYAAkK5gkDJwAeAQAAAA==.Sarnara:BAABNQAECn84AAIMAAoK7xhIFQBXAgAMAAoK7xhIFQBXAgAAAA==.Satyria:BAAANQAECgQJBgAAAA==.Savagedeath:BAAANQAECgQIAwAAAA==.',
Se='Secord:BAABNQAECn8tAAIDAAYK2ALJAAEDAQADAAYK2ALJAAEDAQAAAA==.Seonghwa:BAAANQADCgcIFwAAAA==.Sereniity:BAAANQADCgYIBgABNQAFFAMICQALAD0dAA==.',
Sh='Shadowherc:BAAANQADCgUIBQAAAA==.Shamalicous:BAAANQAECgYIDQAAAA==.Shamous:BAAANQADCgYIDAAAAA==.Shampooh:BAAANQAECgUICAAAAA==.Shanthe:BAAANQADCgUIBQABNQAECgoKMAAPAPwaAA==.Sharku:BAACNQAFFH8IAAIWAAQKgg7DSgCSAAAWAAQKgg7DSgCSAAA1AAQKf08AAxYACgrmHfwrAIQCABYACgrmHfwrAIQCAA0AAQrHF849AEkAAAAA.Shegothalf:BAAANQAECgUICQAAAA==.Shougo:BAAANQADCgQIBAAAAA==.',
Si='Sickem:BAAANQAECgQIBAAAAA==.',
Sk='Skibblé:BAABNQAECn8UAAIaAAYKyAbPKAAzAQAaAAYKyAbPKAAzAQAAAA==.',
Sl='Slickcity:BAAANQADCggICAAAAA==.Slimthick:BAAANQAECgQICAAAAA==.Slimthicka:BAAANQADCggICAAAAA==.',
Sm='Smokeofsteel:BAABNQAECn8ZAAIiAAYKDRofFgBIAQAiAAYKDRofFgBIAQAAAA==.',
So='Solari:BAAANQADCgYICgABNQAECgoKOQAcAPAiAA==.',
Sp='Spinji:BAAANQADCgUIBQAAAA==.Spliff:BAAANQADCggIBAAAAA==.',
St='Stabsmcshank:BAABNQAECn8nAAMOAAoKbhBYIwCuAQAOAAoKTQ1YIwCuAQAPAAUK6hFZXQBBAQAAAA==.Starbux:BAABNQAECn8lAAMgAAoK1A5VVQDQAQAgAAoK1A5VVQDQAQACAAQK3QJ1TABnAAAAAA==.Steakx:BAABNQAECn8/AAIDAAoK0yC9GgAuAwADAAoK0yC9GgAuAwAAAA==.Stormwulf:BAABNQAECn8iAAMTAAgKJBxYSgDSAQATAAgKJBxYSgDSAQAIAAIKCwzsyQBoAAAAAA==.',
Su='Sunmae:BAABNQAECn8WAAIIAAgKIQ4udADFAQAIAAgKIQ4udADFAQABNQAECgkJJgAGAGoUAA==.Suriel:BAABNQAECn8ZAAIKAAYKkgmlVwDTAAAKAAYKkgmlVwDTAAAAAA==.Suumcuique:BAAANQADCggICAABNQAECggIIQARAEIiAA==.',
Sv='Svaha:BAAANQADCgYIEgABNQAECgoKJgADADMRAA==.Svenya:BAABNQAECn8aAAMRAAkKKhDoQwANAQARAAcKeAroQwANAQAlAAMK+AUlowBVAAAAAA==.',
Sy='Sygne:BAAANQAECgYIDgAAAA==.Sylphid:BAABNQAECn8yAAMEAAoKvhaaWwANAgAEAAoKvhSaWwANAgAMAAgKmRGQGgCHAQABNQAFFAYICgAKAGwVAA==.',
Sz='Szell:BAABNQAECn8rAAIDAAkKRAyXgwCWAQADAAkKRAyXgwCWAQAAAA==.',
['Së']='Sëkhmët:BAAANQADCgUIBQABNQADCgMIAwAFAAAAAA==.',
['Sï']='Sïenna:BAAANQADCgQIBAAAAA==.',
Ta='Tacituss:BAAANQABCgMIAwABNQADCgcIEQAFAAAAAA==.Taln:BAAANQADCgUICQAAAA==.Tassandie:BAABNQAECn8wAAMgAAoKHRzZHgDTAgAgAAoKHRzZHgDTAgACAAEKAABZcQAAAAAAAA==.Tayebeh:BAAANQADCgYIFQAAAA==.',
Te='Tektoniik:BAAANQADCgYICQABNQAFFAMICQALAD0dAA==.',
Th='Thatguy:BAAANQAECgcIBgABNQAECgoKLQAWAAMjAA==.Thebrownbear:BAAANQAECggICQAAAA==.Theebucket:BAAANQAECgcIBwAAAA==.Theo:BAAANQAECggIEAABNQAECgoKNgAgADsaAA==.Therese:BAAANQADCgUIBQAAAA==.Theresee:BAAANQADCggIEAAAAA==.Thorylianna:BAAANQADCgYIBgABNQAECgoKQAAKAGsaAA==.',
Ti='Tionie:BAABNQAECn8XAAIDAAkKVQzvcADDAQADAAkKVQzvcADDAQAAAA==.',
To='Toiletnuker:BAAANQADCgUJCQABNQAECgkJLQABABoiAA==.Tokyojoe:BAACNQAFFH8OAAIeAAUK/w4bBQAbAQAeAAUK/w4bBQAbAQA1AAQKfzAAAh4ACgouFf0eAFgCAB4ACgouFf0eAFgCAAAA.Torrick:BAAANQAECggIDwABNQAECgoKMAALALAPAA==.Totemtot:BAABNQAECn8lAAIkAAgK8gMSIgA7AQAkAAgK8gMSIgA7AQAAAA==.Toupee:BAAANQADCgQIBAAAAA==.',
Tr='Tradrivia:BAAANQADCgMIAwABNQAECgoKOQAHAMclAA==.Traelindra:BAAANQADCggIFwAAAA==.Tryxtyflyx:BAAANQAECgEIAQAAAA==.',
Ty='Tydistus:BAAANQADCgMIAwAAAA==.Tygrala:BAAANQADCgYICQABNQAECgoKOAAMAO8YAA==.',
Uf='Uffizzle:BAAANQAECggIDwAAAA==.',
Ul='Ulf:BAABNQAECn85AAITAAoKCSEtGAATAwATAAoKCSEtGAATAwAAAA==.',
Un='Unheardssk:BAAANQADCgQIBAABNQAECgQIDQAFAAAAAA==.Unholycow:BAAANQABCgYICAAAAA==.',
Va='Valquirie:BAABNQAECn9AAAIKAAoKaxrcGgAZAgAKAAoKaxrcGgAZAgAAAA==.Varlamor:BAABNQAECn8jAAMCAAkKhAg1OwBPAQACAAkKhAg1OwBPAQAgAAIK8ALXAwEoAAAAAA==.Varolokiir:BAAANQADCgEIAQABNQAFFAMICQALAD0dAA==.Vathraen:BAAANQADCgYICgAAAA==.',
Ve='Velanistra:BAABNQAECn8iAAIEAAoKSghVsQBXAQAEAAoKSghVsQBXAQAAAA==.Velanya:BAAANQADCgUIBQAAAA==.Velnia:BAAANQAECgMIAwAAAA==.Vervane:BAABNQAECn8zAAIQAAoKWQw6LgCLAQAQAAoKWQw6LgCLAQAAAA==.',
Vg='Vgerr:BAABNQAECn8qAAIEAAkKUAoPwwA3AQAEAAkKUAoPwwA3AQAAAA==.',
Vi='Vidarus:BAAANQADCggICAABNQAFFAUIEQAEALkcAA==.',
Vo='Vohu:BAABNQAECn80AAMDAAoKmxv+TAAgAgADAAkKDR3+TAAgAgAYAAgKWhD0OgB5AQAAAA==.Voidpower:BAABNQAECn8XAAIeAAkKbwerKwAkAQAeAAkKbwerKwAkAQAAAA==.Vozzle:BAAANQADCgQICwAAAA==.',
['Và']='Vàlentine:BAAANQADCgQIBAAAAA==.',
Wa='Walane:BAAANQAECgQIBAAAAA==.Waterlily:BAAANQADCgMIAwAAAA==.',
Wi='Wiglet:BAAANQADCgYIBgAAAA==.Windeyaho:BAABNQAECn8fAAIHAAoK4CP3BQA0AwAHAAoK4CP3BQA0AwAAAA==.',
Xa='Xal:BAAANQAECgQICAABNQAECgoKQAAMAGwgAA==.Xapwv:BAAANQADCgQIBAAAAA==.',
Xe='Xent:BAAANQAECgcIDQAAAA==.',
Xt='Xten:BAABNQAECn8ZAAIRAAYK2RO4NAA0AQARAAYK2RO4NAA0AQAAAA==.',
Yo='Yoshinox:BAABNQAECn9SAAIDAAoK3SEjDAB8AwADAAoK3SEjDAB8AwAAAA==.',
Za='Zalth:BAAANQADCgIIAgAAAA==.',
Ze='Zelliph:BAAANQAECgYIDQAAAA==.Zenagdrina:BAABNQAECn8lAAIDAAoKhAcfjQCAAQADAAoKhAcfjQCAAQAAAA==.Zenobiå:BAABNQAECn89AAIIAAoKMRGkNgDlAQAIAAoKMRGkNgDlAQAAAA==.Zeypher:BAAANQADCgcIGgAAAA==.',
Zh='Zhaann:BAABNQAECn8ZAAMCAAYKJwjiOgCzAAACAAUKcwbiOgCzAAAgAAUKZg6M0wCsAAAAAA==.',
Zi='Zinarra:BAAANQADCgcIBwAAAA==.Ziron:BAAANQADCgIIAgABNQAECgQIDQAFAAAAAA==.Zironlock:BAABNQAECn8WAAIJAAkK0RHjbAAXAgAJAAkK0RHjbAAXAgABNQAECgQIDQAFAAAAAA==.',
Zo='Zorach:BAAANQAECgIIAgAAAA==.',
Zu='Zugga:BAAANQAECggICgABNQAFFAUIDgAeAP8OAA==.',
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

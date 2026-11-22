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

local lookup = {'Paladin-Holy','Priest-Shadow','Rogue-Assassination','Hunter-BeastMastery','Paladin-Retribution','Unknown-Unknown','Druid-Feral','Druid-Guardian','Shaman-Elemental','Druid-Restoration','Warlock-Demonology','DeathKnight-Blood','Evoker-Preservation','Paladin-Protection','Mage-Frost','Rogue-Subtlety','DemonHunter-Havoc','Warrior-Arms','Shaman-Restoration','Monk-Mistweaver','Monk-Windwalker','Mage-Arcane','Hunter-Survival','Hunter-Marksmanship','Warlock-Affliction','Warlock-Destruction','Evoker-Devastation','DeathKnight-Unholy','DeathKnight-Frost','DemonHunter-Devourer','DemonHunter-Vengeance','Priest-Holy','Warrior-Fury','Warrior-Protection','Monk-Brewmaster','Shaman-Enhancement','Druid-Balance','Evoker-Augmentation','Priest-Discipline',}
local provider = {region='US',realm='KhazModan',name='US',type='weekly',zone=53,date='2026-11-17',data={Ad='Advîl:BAABNQAECn8tAAIBAAoKDR2uGwDcAgABAAoKDR2uGwDcAgAAAA==.',
Ae='Aeryhnn:BAAANQADCgcIIgABNQAECgYIHgACAPAGAA==.',
Al='Alarogue:BAABNQAECn8WAAIDAAkKnw5UEgCoAQADAAkKnw5UEgCoAQAAAA==.Alexandre:BAABNQAECn8sAAIEAAoK4RK6hACwAQAEAAoK4RK6hACwAQAAAA==.Allasia:BAAANQAECgUIBwAAAA==.Alterboy:BAAANQADCgIIAgABNQAECgoKMQABAIciAA==.Alton:BAABNQAECn8xAAIBAAoKSg9hWAAQAgABAAoKSg9hWAAQAgAAAA==.',
Am='Amoonsia:BAAANQAECgQIBgAAAA==.',
An='Anfernyphere:BAABNQAECn8VAAMBAAgKyx7VLQCvAgABAAgKyx7VLQCvAgAFAAQK8w/PHwHqAAABNQAECgQIBQAGAAAAAA==.Ansuz:BAAANQAECgIIAQAAAA==.Anvil:BAAANQADCgMIAwAAAA==.',
Ap='Aphroditee:BAAANQADCgUIBQAAAA==.Apostriss:BAAANQADCgMIAwAAAA==.',
Aq='Aquafresh:BAAANQADCgUJBQAAAA==.',
Ar='Arisel:BAABNQAECn8qAAMHAAoKRRSzDgDeAQAHAAoKRRSzDgDeAQAIAAYKRwtGMwAHAQAAAA==.Aristia:BAAANQADCggIDgABNQAFFAQIDAAJALoEAA==.Arweni:BAAANQAECgIIAQAAAA==.',
At='Atheizt:BAABNQAECn8eAAIBAAkKcRtgJwDLAgABAAkKcRtgJwDLAgABNQAECgoKMQAKAN4iAA==.',
Az='Azael:BAAANQADCgcIEAAAAA==.',
Ba='Badned:BAAANQAECggICAAAAA==.Bakachan:BAAANQAECgIIAgAAAA==.Baldilocks:BAAANQADCgQIBAAAAA==.Banedon:BAAANQADCgMJBQABNQAECgoKMQABAIciAA==.Baobob:BAAANQAECgMIAwAAAA==.',
Be='Bearbacked:BAAANQADCgYIBgABNQAECgUIDgAGAAAAAA==.Beastmaster:BAAANQAECgMIAwAAAA==.Beetingu:BAAANQADCgcIFgABNQAECgkJJwALAMsiAA==.Belashar:BAAANQADCgYIGAAAAA==.Beytuha:BAABNQAECn9BAAIIAAoK3SU0AgBaAwAIAAoK3SU0AgBaAwAAAA==.',
Bi='Bighornygay:BAAANQAECggIBQAAAA==.Bigsmoke:BAAANQADCgUIBQAAAA==.',
Bl='Blacken:BAABNQAECn8gAAIMAAcK6xkkQgA1AQAMAAcK6xkkQgA1AQAAAA==.Blackknife:BAAANQADCgQIBAAAAA==.Bladestorm:BAAANQAECgYICQABNQAFFAQICgANAFAeAA==.Blakylightz:BAABNQAECn8bAAMFAAkKwhqZaQD9AQAFAAgKRhmZaQD9AQAOAAQKqh3xJABHAQABNQAFFAIIBAAGAAAAAA==.Blazen:BAABNQAECn8sAAIJAAoKESB/IAAJAwAJAAoKESB/IAAJAwAAAA==.Blinker:BAABNQAECn8iAAIPAAkKXguEEQB2AQAPAAkKXguEEQB2AQAAAA==.Bloodynuts:BAABNQAECn8cAAMQAAkKqhOAFwAiAgAQAAgKURSAFwAiAgADAAIKzhImjwB1AAAAAA==.Bloyfbloyf:BAACNQAFFH8HAAIRAAQKzgQpFACZAAARAAQKzgQpFACZAAA1AAQKfywAAhEACgoBGRgZAEwCABEACgoBGRgZAEwCAAAA.Blueberriess:BAAANQAECgQIBAAAAA==.Blueshadøw:BAAANQADCgcIBwAAAA==.',
Bo='Bobbidyboo:BAACNQAFFH8ZAAIKAAYKNwY+CABcAQAKAAYKNwY+CABcAQA1AAQKf0IAAgoACgoVE+4kAPwBAAoACgoVE+4kAPwBAAAA.Bocknot:BAAANQAECgEIAQAAAA==.Bonesclone:BAAANQAECgQIBgAAAA==.',
Br='Brewshido:BAAANQAECgIIBQAAAA==.Briareosx:BAABNQAECn89AAISAAoKDxz8SACvAgASAAoKDxz8SACvAgAAAA==.Brixtia:BAAANQADCgcIBgABNQAECgoKPAAEAP4bAA==.Brovar:BAACNQAFFH8bAAIFAAYKch0UCQBbAQAFAAYKch0UCQBbAQA1AAQKf0MAAgUACgpHJDIWAGwDAAUACgpHJDIWAGwDAAAA.',
Bu='Bubbaa:BAABNQAECn8hAAMTAAkKrR/+IQDgAgATAAkKrR/+IQDgAgAJAAEKAAAMJAFJAAAAAA==.Buddydaelf:BAABNQAECn8rAAIEAAoKKxgwOwBiAgAEAAoKKxgwOwBiAgAAAA==.',
Bw='Bwonsamdî:BAAANQAECgIIAwAAAA==.Bwonshlongdi:BAAANQADCgYIBgAAAA==.',
Ca='Cathexis:BAAANQADCggIEAABNQAECgoKMAANALAPAA==.',
Ce='Ceanaflowers:BAABNQAECn8ZAAISAAoKrRBwjAD9AQASAAoKrRBwjAD9AQAAAA==.',
Ch='Challah:BAAANQAECgMIBAAAAA==.Chia:BAABNQAECn8zAAMUAAoKiBhdDABqAgAUAAoKiBhdDABqAgAVAAIKnQaEYQBZAAABNQADCgMIAwAGAAAAAA==.Chianamoya:BAAANQADCgcIFwABNQAECgYIGQAMAJIJAA==.Chune:BAAANQADCgQIBAAAAA==.',
Cl='Clarisse:BAAANQAECgMIAQABNQAECgoKRAAMAGsaAA==.',
Co='Coldburn:BAAANQADCgQIBAAAAA==.Connor:BAAANQAECgQICQAAAA==.Coolarrow:BAABNQAECn8tAAIEAAkKPxsINgBxAgAEAAkKPxsINgBxAgABNQAFFAQIFgAEAB4fAA==.Cosby:BAAANQADCgEIAQAAAA==.',
Cr='Cracken:BAAANQABCgYIBgAAAA==.Croissantx:BAABNQAECn8ZAAIWAAcKGBAQuQAzAQAWAAcKGBAQuQAzAQAAAA==.Crosshair:BAABNQAECn8fAAMXAAcKTxMqCQBYAQAXAAcKTxMqCQBYAQAYAAEKXAHingAfAAAAAA==.',
Cu='Cutpo:BAAANQAECgQIBAABNQAFFAcIFQALAMIQAA==.',
Cy='Cyndrenissa:BAAANQADCgEIAQAAAA==.Cynris:BAAANQAECgEIAQABNQAECgoKQAAOAGwgAA==.',
['Cê']='Cêlaçane:BAAANQADCgIJAgAAAA==.',
Da='Dacianstorm:BAAANQADCgIIAgAAAA==.Dacianwolf:BAAANQAECggICwAAAA==.Dagaz:BAAANQADCgUIBQAAAA==.Dagrim:BAAANQAECggICAAAAA==.Daravinius:BAAANQAECgYIDgAAAA==.Dare:BAAANQAECgQJBwAAAA==.Davaeh:BAAANQADCgIIAgABNQAECgoKMQABAIciAA==.Davandar:BAAANQADCgYIDAAAAA==.Daveah:BAABNQAECn8wAAITAAoKGgnnZQCEAQATAAoKGgnnZQCEAQAAAA==.',
De='Deathberry:BAABNQAECn87AAILAAkKNQ+TZQClAQALAAkKNQ+TZQClAQAAAA==.Deathsmoke:BAAANQADCgEIAQAAAA==.Delphron:BAAANQAECgIIAgAAAA==.Demoncharge:BAAANQAECgEIAgAAAA==.Demonflayer:BAAANQAECgEIAQABNQAECgEIAgAGAAAAAA==.Demonlust:BAAANQAECgEIAQABNQAECgEIAgAGAAAAAA==.Denaeaa:BAABNQAECn8YAAMUAAcKYBeXGQDmAQAUAAcKYBeXGQDmAQAVAAIKlgBHZAAjAAABNQAFFAQICAATAIAFAA==.Depala:BAAANQADCgcIEAABNQAECgIIAgAGAAAAAA==.Devilzkry:BAAANQADCgUIBQAAAA==.Devistaysha:BAABNQAECn88AAMJAAoK8RO2OQDtAQAJAAoK8RO2OQDtAQATAAEKvgH9DAEhAAAAAA==.',
Dh='Dharmakat:BAAANQADCgUICQAAAA==.',
Di='Dist:BAAANQAECgMICQAAAA==.Divinestorm:BAABNQAECn8xAAMBAAoKhyJdHQDQAgABAAgKmCFdHQDQAgAFAAkKUw5rpACFAQAAAA==.Divinethis:BAAANQADCgIIAgAAAA==.',
Dn='Dnyal:BAAANQAECggIEAAAAA==.',
Do='Dodgysenpai:BAAANQADCgUIBQABNQAECgoKPwASAJUmAA==.Dogbreathrlz:BAAANQABCgUIBwAAAA==.Dolomite:BAAANQAECgIIBgAAAA==.Dookerslol:BAAANQADCgUIAwAAAA==.Dotexe:BAABNQAECn80AAIDAAgKXx2nDQDwAQADAAgKXx2nDQDwAQAAAA==.Dotsy:BAACNQAFFH8eAAQZAAcKKRtwAQBaAQAZAAYK8R1wAQBaAQALAAUKJhrAFgDxAAAaAAEKlxOOGgBQAAA1AAQKf0YABBoACgqjIVgTANcBAAsACQrPIJUzALsCABoABgoXH1gTANcBABkABwqUHgUOAFYBAAAA.',
Dr='Drackarys:BAAANQADCgcIIgAAAA==.Dragooner:BAAANQADCgMIAwAAAA==.Drakiir:BAACNQAFFH8KAAMNAAQKUB5LCwBSAQANAAQKUB5LCwBSAQAbAAIKCSN4BACqAAA1AAQKf0cAAw0ACgrTI04DAIMDAA0ACgrTI04DAIMDABsACAqpIH4PAGICAAAA.Dralkish:BAAANQAECgEIAQAAAA==.Drathi:BAABNQAECn8wAAMNAAoKsA8tIgC6AQANAAoKsA8tIgC6AQAbAAcKcw2QIQBCAQAAAA==.Dravas:BAAANQAECgUICgAAAA==.Draxis:BAAANQADCggIDgAAAA==.Drezzo:BAAANQADCgcIFgAAAA==.Dryerbro:BAAANQABCgUIBQAAAA==.Drzark:BAABNQAECn8aAAIPAAYKYwePHQDnAAAPAAYKYwePHQDnAAAAAA==.',
Du='Duskwulf:BAAANQADCgMIBQABNQAECgoKJAATADcZAA==.',
Dw='Dwdog:BAABNQAECn8nAAIZAAkK7g+DCADUAQAZAAkK7g+DCADUAQAAAA==.',
['Dà']='Dàthguy:BAABNQAECn9EAAIcAAoKFyVpAwC+AwAcAAoKFyVpAwC+AwAAAA==.',
['Dé']='Défault:BAABNQAECn8yAAMcAAoKIh4wEwAfAwAcAAoKIh4wEwAfAwAdAAQKOA0hcwDTAAAAAA==.',
Ed='Edaras:BAAANQAECgIIAwAAAA==.Edredria:BAAANQABCgIIAgAAAA==.',
Ef='Effrøn:BAAANQAECgUIBQAAAA==.',
Ei='Eilybellea:BAAANQAECgEIAQAAAA==.',
El='Elek:BAAANQAECgYICwABNQAFFAUIBwAaAIsRAA==.Elennie:BAAANQAECgIIAgAAAA==.Elista:BAAANQABCgcICAAAAA==.',
Em='Emmi:BAABNQAECn8iAAIcAAkKuRcJIQDZAQAcAAkKuRcJIQDZAQAAAA==.',
En='Enyo:BAABNQAECn8oAAIeAAkKQRQnJgAUAgAeAAkKQRQnJgAUAgAAAA==.',
Er='Erad:BAAANQADCgcIDAAAAA==.',
Ev='Evilritê:BAAANQADCggIEQAAAA==.Evilspawn:BAAANQADCgQIBAAAAA==.',
Ex='Excalipoor:BAAANQADCgQIBAAAAA==.',
Fa='Faloran:BAAANQAECgQICQAAAA==.Farstad:BAAANQADCgUIBQAAAA==.Fayereadmore:BAAANQADCggICgAAAA==.',
Fe='Fearmyhunter:BAAANQADCggJCQAAAA==.Fekk:BAAANQADCggIDgABNQAECggIDwAGAAAAAA==.Felsmoke:BAAANQADCgYIBgAAAA==.Fervid:BAABNQAECn8qAAIWAAgKABNfqABTAQAWAAgKABNfqABTAQAAAA==.Feylen:BAABNQAECn8yAAIWAAoK4SUkCgCvAwAWAAoK4SUkCgCvAwAAAA==.',
Fi='Fido:BAABNQAECn8sAAIMAAkKhBDMNgBqAQAMAAkKhBDMNgBqAQAAAA==.Fidø:BAAANQADCgUIDwABNQAECgkJLAAMAIQQAA==.Fifthelement:BAABNQAECn87AAITAAoK8CI0CwBuAwATAAoK8CI0CwBuAwAAAA==.Figgson:BAAANQADCgQIBAAAAA==.Figgy:BAABNQAECn8lAAITAAgK7haKYQCTAQATAAgK7haKYQCTAQAAAA==.Fiorstrasza:BAABNQAECn8yAAMNAAoKMRaADgApAgANAAoKMRaADgApAgAbAAIKbwZNNgBcAAAAAA==.Firry:BAAANQADCgYIEgAAAA==.Fistsofsmoke:BAAANQADCgUICAAAAA==.',
Fj='Fjalgeirr:BAABNQAECn8+AAMRAAoKxRAjKQDFAQARAAoKxRAjKQDFAQAfAAEKAADSPQAFAAAAAA==.',
Fl='Flockling:BAAANQADCggIDQAAAA==.',
Fo='Forshure:BAAANQAECgQIBAAAAA==.Foxymomma:BAABNQAECn8nAAIgAAkK0RjpPABHAgAgAAkK0RjpPABHAgAAAA==.',
Fr='Freaksbetter:BAAANQAECgYIBgAAAA==.Froot:BAAANQAECgUIDgAAAA==.Frßlizzard:BAAANQAECgEIAQAAAA==.Frìga:BAAANQADCgUIBQAAAA==.',
Fu='Fulgar:BAABNQAECn9AAAIFAAoKHSDGLgAOAwAFAAoKHSDGLgAOAwAAAA==.',
Ga='Galatea:BAAANQAECgUIBQAAAA==.Gaëll:BAAANQAECgEIAQAAAA==.',
Ge='Gearsprocket:BAABNQAECn8hAAQhAAoKFRSVDADyAQAhAAoKFRSVDADyAQAiAAMK0gYSMgB8AAASAAIKlgWaJwE5AAABNQAECgoKMQABAEoPAA==.Geosmin:BAABNQAECn8bAAITAAkKsBAuYwDkAQATAAkKsBAuYwDkAQAAAA==.Geronimoose:BAAANQADCgYJDAABNQAECgoKMQABAEoPAA==.',
Gh='Ghue:BAABNQAECn8eAAMOAAoKgAtEIwBUAQAOAAoKyQlEIwBUAQAFAAYKMwzQAgEbAQAAAA==.Ghòst:BAAANQAECgMIAgAAAA==.',
Gi='Gilalade:BAABNQAECn8iAAIEAAkKvRVZdADXAQAEAAkKvRVZdADXAQAAAA==.Girlboss:BAAANQADCgQIBAAAAA==.',
Gl='Glissa:BAAANQAECgIIAgABNQAECgoKKwAbAEcYAA==.',
Go='Gobann:BAAANQAECgUIBQABNQAECgoKPAAEAP4bAA==.Gonern:BAABNQAECn9AAAMOAAoKbCDQCgDuAgAOAAoKJB7QCgDuAgAFAAkKvByUewDWAQAAAA==.Gooby:BAACNQAFFH8TAAIgAAYKrhQJEAClAQAgAAYKrhQJEAClAQA1AAQKfyQAAyAACgqYGes0AGsCACAACgqYGes0AGsCAAIAAQrvAImTABUAAAAA.Goond:BAAANQAECgcIDQABNQAFFAUIBwAaAIsRAA==.Gooney:BAAANQAECgQIBgAAAA==.Gotwood:BAAANQADCgYIBgAAAA==.',
Gr='Gravestorm:BAAANQABCggIIQAAAA==.Grimes:BAAANQADCgcIBwABNQAECgUIDgAGAAAAAA==.Grlfriend:BAAANQAECgUIDQAAAA==.Grodin:BAAANQAECgUIBQAAAA==.Grofiest:BAABNQAECn8yAAMCAAoKaRKMFwDtAQACAAoKaRKMFwDtAQAgAAEKoAFHBAEaAAAAAA==.',
Gu='Gugg:BAAANQADCgIJAgABNQAECgoKPwASAJUmAA==.Guggychan:BAABNQAECn8/AAMSAAoKlSbpAgDkAwASAAoKdSbpAgDkAwAhAAMKTSYDHADVAAAAAA==.Guggys:BAAANQAECgQIBAAAAA==.Gunslinger:BAAANQAECggIDwAAAA==.Gunsmoke:BAAANQAECgEIAQAAAA==.',
Gw='Gwynbleidd:BAABNQAECn9FAAIMAAoK0RC7LwCQAQAMAAoK0RC7LwCQAQAAAA==.',
Ha='Hadrian:BAAANQADCgYIDwAAAA==.Haldor:BAAANQADCgcIBwAAAA==.Hanohakua:BAAANQADCgcIDgAAAA==.Haohmaru:BAABNQAECn8nAAIjAAkKsBs9CgByAgAjAAkKsBs9CgByAgAAAA==.Harthen:BAAANQADCgcIGAABNQAECgoKKgAHAEUUAA==.Hashbrowns:BAAANQADCgIIAgAAAA==.',
He='Hellßoy:BAAANQADCgUICwAAAA==.Herc:BAAANQAECgIIAgAAAA==.Hercgrim:BAABNQAECn8WAAQhAAcKHhQEGQARAQASAAYK2xBL4AApAQAhAAQKOhsEGQARAQAiAAEK8gyJRwAmAAAAAA==.Hercsham:BAAANQAECgIIAgAAAA==.Herger:BAAANQABCgYICgAAAA==.',
Hi='Hipsta:BAABNQAECn8gAAIFAAoK7gnU1QBwAQAFAAoK7gnU1QBwAQAAAA==.',
Ho='Hollowshkari:BAAANQADCgYICAAAAA==.Holyclunge:BAAANQAECggICwAAAA==.Holypower:BAAANQADCgcIBwAAAA==.Horexion:BAAANQADCgUJBQAAAA==.',
Hp='Hplaysgames:BAAANQADCgYIBgAAAA==.',
Hu='Huneyb:BAAANQADCgYIEgAAAA==.Huneyhunter:BAABNQAECn8gAAIHAAgKsweYIgD8AAAHAAgKsweYIgD8AAAAAA==.',
Ic='Ichigozero:BAAANQADCgUIBwAAAA==.',
Ig='Igor:BAAANQABCgQIAgAAAA==.',
Il='Illimommy:BAAANQADCgYICwAAAA==.',
In='Intern:BAAANQAECgYIDQAAAA==.',
Ir='Ironaxe:BAABNQAECn87AAIEAAoKtA0sbgDlAQAEAAoKtA0sbgDlAQAAAA==.',
It='Itsademon:BAAANQAECgYICwAAAA==.',
Ja='Jaeksoolie:BAABNQAECn8XAAMkAAgKxg/iFgD7AQAkAAgKxg/iFgD7AQAJAAEKAACxOgExAAAAAA==.Jakyro:BAABNQAECn8nAAMNAAkKbQrJLABAAQANAAkKbQrJLABAAQAbAAYK/A4ZFgDVAAAAAA==.Javeech:BAABNQAECn8eAAIFAAcKlhqtlwD0AQAFAAcKlhqtlwD0AQAAAA==.Jaypark:BAABNQAECn8dAAIVAAkK7BX0HgA5AgAVAAkK7BX0HgA5AgAAAA==.Jayse:BAABNQAECn8ZAAMhAAoKfgmlFABVAQAhAAoKWwmlFABVAQASAAQK8gR2HQGhAAABNQAECgoKJgAJAKAhAA==.',
Jc='Jchaotic:BAAANQADCgUIBQAAAA==.',
Je='Jeezus:BAAANQAECgQIBAABNQAFFAYICgAMAGwVAA==.Jeren:BAAANQADCggIDAAAAA==.Jesophocles:BAAANQADCgUICgAAAA==.',
Jo='Joole:BAAANQADCgIIAgABNQAECgYIHgACAPAGAA==.Joru:BAAANQADCgUIBQAAAA==.Jovero:BAABNQAECn82AAMQAAoKSBnHJAByAgAQAAoKSBnHJAByAgADAAEK6RAMYgA5AAAAAA==.',
Ju='Juanda:BAABNQAECn8YAAIJAAcKLCHcLAApAgAJAAcKLCHcLAApAgAAAA==.Junghee:BAABNQAECn9KAAMUAAoKoyNmBQBLAwAUAAoKoyNmBQBLAwAVAAcKxhUeLQCwAQAAAA==.Juudaz:BAACNQAFFH8KAAIMAAYKbBWdEgAtAQAMAAYKbBWdEgAtAQA1AAQKf4QABAwACgpJJbkDAEkDAAwACgpaJLkDAEkDABwACgorJI0GAA0DAB0ACAoCFuNCALkBAAAA.',
['Jï']='Jïnx:BAABNQAECn80AAIJAAoK9iIuDwD0AgAJAAoK9iIuDwD0AgAAAA==.',
Ka='Kaalhvel:BAABNQAECn8WAAIEAAYK8wW25QA1AQAEAAYK8wW25QA1AQAAAA==.Kaeric:BAAANQADCgQIBAAAAA==.Kakahna:BAABNQAECn8oAAQBAAkK0Rz3MwBOAgABAAkK0Rz3MwBOAgAFAAQKGgtBQgGMAAAOAAIKIQuPVABbAAAAAA==.Kapkywa:BAABNQAECn8xAAIKAAoK3iLIAgDjAwAKAAoK3iLIAgDjAwAAAA==.Kasherquon:BAAANQAECgQIDAABNQAECgUICAAGAAAAAA==.Katsumyo:BAAANQADCggIGQAAAA==.Kawaiimonsta:BAAANQADCggICAAAAA==.',
Ke='Kellyx:BAAANQAECgMIAwAAAA==.',
Kh='Khazmcknight:BAAANQADCgEIAQAAAA==.',
Ki='Killersmile:BAAANQADCggIDgAAAA==.Kilra:BAABNQAECn8gAAIJAAgKBwXulwDYAAAJAAgKBwXulwDYAAAAAA==.Kiyara:BAABNQAECn88AAIEAAoKAhY1SgA7AgAEAAoKAhY1SgA7AgAAAA==.Kizaki:BAABNQAECn8VAAIeAAYKyx2eKQD2AQAeAAYKyx2eKQD2AQAAAA==.',
Kn='Knowoone:BAAANQAECgEIAQAAAA==.',
Ko='Kouelwhip:BAAANQADCgYIBgABNQAFFAQICgANAFAeAA==.',
Kr='Krelliz:BAABNQAECn83AAMTAAoKKxCwbADFAQATAAoKKxCwbADFAQAJAAYKIgf4lADfAAAAAA==.Krolly:BAAANQAECgQICQAAAA==.Krystar:BAABNQAECn8VAAIFAAYKERGW7ABDAQAFAAYKERGW7ABDAQAAAA==.',
Ku='Kungfuwho:BAABNQAECn8lAAQUAAoKTgu2IQB5AQAUAAoKTgu2IQB5AQAVAAUK/QdbTwC4AAAjAAEKAADbNgAdAAAAAA==.Kunoíchi:BAAANQADCgcIBwABNQAECgYIFQAeAMsdAA==.',
Kw='Kwassass:BAAANQADCgYIBgAAAA==.',
La='Laysee:BAAANQAECgIIAgAAAA==.',
Le='Legendomega:BAAANQAECgMIAwAAAA==.Leksa:BAAANQABCgEIAQAAAA==.Lenaea:BAACNQAFFH8IAAITAAQKgAWGGADrAAATAAQKgAWGGADrAAA1AAQKf0UAAxMACgoBFjZBAFwCABMACgoBFjZBAFwCAAkABgoDD5OZANUAAAAA.',
Li='Liiege:BAAANQAECggIDwABNQAFFAQICgANAFAeAA==.Likeàßoss:BAAANQADCgIIAgAAAA==.Linlithyr:BAABNQAECn85AAMOAAoKuxovEQAYAgAOAAoKuxovEQAYAgAFAAEKAADk0wEAAAABNQAECgoKRAAMAGsaAA==.',
Lo='Lobø:BAABNQAECn8uAAIEAAoKQBI6jADyAQAEAAoKQBI6jADyAQAAAA==.Lowtierscrub:BAAANQAECgUIBwABNQAECgoKGQASAK0QAA==.',
Lu='Luccyy:BAAANQADCgQICwAAAA==.Lunacaris:BAAANQADCgQIBAAAAA==.Lunamoss:BAAANQADCgYIBgAAAA==.Lunatyc:BAABNQAECn82AAIcAAoKig4oKAChAQAcAAoKig4oKAChAQAAAA==.Luth:BAAANQADCggICAABNQAECgUIEwAGAAAAAA==.Luthex:BAAANQAECgUIEwAAAA==.',
Ly='Lylacy:BAABNQAECn9NAAILAAoKThHcVADVAQALAAoKThHcVADVAQAAAA==.Lynx:BAAANQAECgUICQABNQADCgMIAwAGAAAAAA==.Lyrea:BAAANQABCgEIAQAAAA==.',
Ma='Macnificent:BAAANQAECgEIAQAAAA==.Madscience:BAABNQAECn8lAAIWAAgKJAUeIAFWAQAWAAgKJAUeIAFWAQAAAA==.Magiicae:BAAANQADCgIIAgABNQAFFAQICgANAFAeAA==.Magnues:BAAANQADCggICAAAAA==.Magoliko:BAAANQAECgEIAgAAAA==.Marqfourthre:BAAANQABCgYIBwAAAA==.Maygwyn:BAAANQADCggICgAAAA==.',
Me='Meanshami:BAAANQAECgEIAQAAAA==.Meatlovers:BAABNQAECn8rAAIKAAkKWBsXGABWAgAKAAkKWBsXGABWAgAAAA==.Medb:BAAANQADCggIDQAAAA==.Medy:BAAANQAECggICAAAAA==.Melar:BAABNQAECn9DAAMhAAoKSBJTCwDYAQAhAAoKSBJTCwDYAQAiAAYKyQolKwCnAAAAAA==.Meowmeowmew:BAAANQADCgUIBQABNQAECgoKMQABAIciAA==.',
Mi='Minjae:BAABNQAECn8YAAILAAcK8g8mfABqAQALAAcK8g8mfABqAQABNQAECgoKSgALAP0XAA==.Misfirë:BAAANQAECgQIDQABNQAECgoKMgAcACIeAA==.',
Mo='Mogwaí:BAABNQAECn8lAAMUAAoK2wyvGQBoAQAUAAoK2wyvGQBoAQAVAAIK7QgZXQA2AAAAAA==.Moondemon:BAAANQADCggIHwAAAA==.Morrìgan:BAAANQAECgMIAgAAAA==.Morvane:BAAANQADCgYICQABNQAECgoKMQABAEoPAA==.Movack:BAABNQAECn8ZAAIFAAgKwQph3wBcAQAFAAgKwQph3wBcAQAAAA==.Mowri:BAAANQABCgUICQAAAA==.',
Mu='Multicrit:BAAANQADCgIIAgAAAA==.Murderface:BAABNQAECn8jAAMKAAkKOSLJMgBbAQAKAAQKzSDJMgBbAQAlAAkKvgmMRgAJAQAAAA==.',
My='Mythunran:BAABNQAECn8/AAIYAAoK3AkQGgCzAQAYAAoK3AkQGgCzAQAAAA==.',
['Mö']='Mörï:BAABNQAECn8aAAIFAAgK+wtqzwB8AQAFAAgK+wtqzwB8AQAAAA==.',
Na='Naethanial:BAAANQAECgYICQAAAA==.Nas:BAAANQAECgQICQAAAA==.Natalina:BAAANQADCgcJCgABNQAECgIIAgAGAAAAAA==.Nav:BAAANQAECgUIBQAAAA==.Nax:BAAANQAECgUIEAAAAA==.Naz:BAAANQAECgEIAQAAAA==.',
Ne='Nerfhammer:BAACNQAFFH8RAAIFAAUKuRxXDACEAQAFAAUKuRxXDACEAQA1AAQKf0QAAgUACgoZJfEWAGkDAAUACgoZJfEWAGkDAAAA.Nessalove:BAACNQAFFH8dAAIgAAYKPhP1DgC4AQAgAAYKPhP1DgC4AQA1AAQKf0YAAiAACgrBHDo4AIcCACAACgrBHDo4AIcCAAAA.Neutrino:BAAANQAECgYIDgAAAA==.',
Ni='Nicolbowlass:BAABNQAECn8fAAMbAAoKARFcCQDlAQAbAAoKARFcCQDlAQAmAAEKBgjPJQAtAAAAAA==.Nightomen:BAAANQADCggICAABNQAECgkJIwAKADkiAA==.Nipao:BAAANQADCgQIBAAAAA==.Nitafart:BAAANQAECgQICAABNQAECgUIDgAGAAAAAA==.',
No='Noone:BAABNQAECn9EAAMTAAoKdhODQgAKAgATAAoKdhODQgAKAgAJAAYKwQmltAApAQAAAA==.Noriel:BAAANQAECgYIDgAAAA==.',
Nz='Nz:BAAANQAECgYICwAAAA==.',
Od='Oddeccentric:BAAANQAECgYIDQABNQAFFAcIFQAiALgWAA==.',
Og='Ognyal:BAAANQAECggICAAAAA==.',
On='Onemanarmyy:BAAANQADCgIIAgABNQADCgMIAwAGAAAAAA==.Onna:BAAANQADCgMIAwAAAA==.',
Oo='Ooblitoon:BAAANQAECggICAAAAA==.',
Op='Opali:BAABNQAECn8bAAMOAAcKTxNUMgBOAQAOAAYKPRJUMgBOAQAFAAYKYhCz0QA1AQAAAA==.',
Os='Osanar:BAABNQAFFH8PAAINAAYKGgMGDAA9AQANAAYKGgMGDAA9AQAAAA==.',
Ov='Oven:BAAANQADCgQIAwABNQAECgoKRAAcABclAA==.Overburned:BAAANQAECgUIBQAAAA==.Overshoot:BAABNQAECn8yAAIEAAoK7BPJawDrAQAEAAoK7BPJawDrAQAAAA==.',
Ox='Oxen:BAAANQADCgUIBQAAAA==.',
Pa='Pallysmoke:BAAANQADCgUIBQAAAA==.Panterion:BAAANQAECgQIBgABNQAECgoKOAAgAGEeAA==.Papimonk:BAAANQAECgQIBwABNQAECgkJIwATAIwcAA==.Parvarti:BAABNQAECn8lAAMaAAYKvwSQRwCpAAALAAYKcgRU8gDlAAAaAAUKxgGQRwCpAAAAAA==.Pathogenic:BAABNQAECn8WAAICAAYKWRMEOABlAQACAAYKWRMEOABlAQAAAA==.Pathologist:BAAANQADCggICAABNQAECggIFgACAFkTAA==.Pavin:BAAANQAECggICAAAAA==.',
Pe='Peluquin:BAAANQADCgIIAgAAAA==.Persimmoñ:BAAANQADCggJEgAAAA==.',
Po='Pokeranger:BAAANQAECgEIAQAAAA==.Polkadott:BAABNQAECn8nAAQLAAkKyyIlVQDUAQALAAcKECMlVQDUAQAaAAIKHCIQGQCYAAAZAAEKAADnNAAAAAAAAA==.',
Pr='Presidìum:BAABNQAECn8eAAIOAAgKzhFcJgA9AQAOAAgKzhFcJgA9AQAAAA==.Procbiscuit:BAAANQAECgYJDAAAAA==.Prost:BAABNQAECn8zAAIPAAoKlh+KBACjAgAPAAoKlh+KBACjAgAAAA==.Provoked:BAAANQAECgQIBQABNQAECgoKKQATAGIbAA==.',
Ps='Psylocke:BAABNQAECn8uAAIDAAkKRg0rGABnAQADAAkKRg0rGABnAQAAAA==.',
Pu='Pugshammy:BAAANQAECgMIAwAAAA==.Purdy:BAAANQAECggICAAAAA==.',
Py='Pyroblast:BAAANQAECgUIBwABNQAECgkJHAAQAKoTAA==.',
Ra='Raedon:BAAANQAECgQIBAAAAA==.Rah:BAAANQAECgUICAABNQAECgoKLwAMAFkWAA==.Rahuwu:BAAANQAECgMIAwABNQAECgoKPwASAJUmAA==.Raveger:BAAANQADCgYIDwABNQAECgoKMQABAIciAA==.',
Re='Reladin:BAABNQAECn8mAAIOAAkKvgryKwAXAQAOAAkKvgryKwAXAQAAAA==.Relaeha:BAAANQADCgEIAQAAAA==.Rendaelyne:BAAANQADCggIJwAAAA==.Renzr:BAABNQAECn86AAMcAAoK8CJOHADiAgAcAAoKzSBOHADiAgAMAAcKPSNoHgC/AgAAAA==.Resectum:BAAANQADCgUIBQAAAA==.Retpally:BAAANQADCgMIAwAAAA==.Rexas:BAAANQAECgUICAABNQAFFAgIIwAbAIcbAA==.',
Ro='Roag:BAABNQAECn8YAAIWAAcKYAp08wDJAAAWAAcKYAp08wDJAAAAAA==.Roley:BAABNQAECn82AAIKAAoKIRAaJQDLAQAKAAoKIRAaJQDLAQAAAA==.Rowin:BAAANQAECgcIEwAAAA==.',
Ru='Rustedroots:BAAANQADCgUIBQAAAA==.',
Sa='Sacrosanct:BAAANQADCgIIAgAAAA==.Sansara:BAAANQAECgUIBQABNQAECgYIGQAMAJIJAA==.Sapphyre:BAAANQABCgQIBgAAAA==.Saristelonio:BAAANQAECgMIAwABNQAECgoKKgAYAEELAA==.Saristrix:BAABNQAECn8qAAIYAAoKQQvCGgCsAQAYAAoKQQvCGgCsAQAAAA==.Sarnara:BAABNQAECn9AAAIOAAoKrRlIFQBXAgAOAAoKrRlIFQBXAgAAAA==.Satyria:BAAANQAECgQJBgAAAA==.Savagedeath:BAAANQAECgQIAwAAAA==.',
Se='Secord:BAABNQAECn8xAAIEAAkK4AP63gD0AAAEAAkK4AP63gD0AAAAAA==.Seonghwa:BAAANQADCgcIFwAAAA==.Sereniity:BAAANQADCgYIBgABNQAFFAQICgANAFAeAA==.',
Sh='Shadowherc:BAAANQADCgUIBQAAAA==.Shamalicous:BAAANQAECgYIDQAAAA==.Shamous:BAAANQADCgYIDAAAAA==.Shampooh:BAAANQAECgUICAAAAA==.Shanthe:BAAANQADCgUIBQABNQAECgoKMAADAPwaAA==.Sharku:BAACNQAFFH8JAAIWAAUKIg0uNwCXAAAWAAUKIg0uNwCXAAA1AAQKf08AAxYACgrmHXYwAH8CABYACgrmHXYwAH8CAA8AAQrHF849AEkAAAAA.Shegothalf:BAAANQAECgQICQAAAA==.Shougo:BAAANQADCgQIBAAAAA==.',
Si='Sickem:BAAANQAECgQIBAAAAA==.Simgear:BAAANQADCgIIAgAAAA==.',
Sk='Skibblé:BAABNQAECn8UAAIaAAYKyAbPKAAzAQAaAAYKyAbPKAAzAQAAAA==.',
Sl='Slickcity:BAAANQADCggICAAAAA==.Slimthick:BAAANQAECgQICAAAAA==.Slimthicka:BAAANQADCggICAAAAA==.',
Sm='Smokeofsteel:BAABNQAECn8ZAAIiAAYKDRrRGABEAQAiAAYKDRrRGABEAQAAAA==.',
So='Solari:BAAANQADCgYICgABNQAECgoKOgAcAPAiAA==.',
Sp='Spinji:BAAANQADCgUIBQAAAA==.Spliff:BAAANQADCggIAwAAAA==.',
St='Stabsmcshank:BAABNQAECn8nAAMQAAoKbhBYIwCuAQAQAAoKTQ1YIwCuAQADAAUK6hFZXQBBAQAAAA==.Starbux:BAABNQAECn8mAAMgAAoK1A7RWwDPAQAgAAoK1A7RWwDPAQACAAQK3QKCUQBnAAAAAA==.Steakx:BAABNQAECn9DAAIEAAoK5SC9GgAuAwAEAAoK5SC9GgAuAwAAAA==.Stormwulf:BAABNQAECn8kAAMTAAoKNxnjOAA1AgATAAoKNxnjOAA1AgAJAAIKCwyv1ABoAAAAAA==.',
Su='Sunmae:BAABNQAECn8WAAIJAAgKIQ4udADFAQAJAAgKIQ4udADFAQABNQAECgoKKgAHAEUUAA==.Suriel:BAABNQAECn8ZAAIMAAYKkglJXQDNAAAMAAYKkglJXQDNAAAAAA==.Suumcuique:BAAANQADCggICAABNQAECgkJIwAKADkiAA==.',
Sv='Svaha:BAAANQADCgYIEgABNQAECgoKLAAEAOESAA==.Svenya:BAABNQAECn8dAAMKAAkKKhDoQwANAQAKAAcKeAroQwANAQAlAAUKVwYYZwCLAAAAAA==.',
Sy='Sygne:BAAANQAECgYIEAAAAA==.Sylphid:BAABNQAECn8zAAMFAAoKvhbHZQAGAgAFAAoKvhTHZQAGAgAOAAgKmRGVHQCDAQABNQAFFAYICgAMAGwVAA==.',
Sz='Szell:BAABNQAECn8vAAIEAAoKxQ0RbwDjAQAEAAoKxQ0RbwDjAQAAAA==.',
['Së']='Sëkhmët:BAAANQADCgUIBQABNQADCgMIAwAGAAAAAA==.',
['Sï']='Sïenna:BAAANQADCgQIBAAAAA==.',
Ta='Tacituss:BAAANQABCgMIAwABNQADCgcIEQAGAAAAAA==.Taln:BAAANQADCgUICQAAAA==.Tassandie:BAABNQAECn84AAMgAAoKYR6+HQDuAgAgAAoKYR6+HQDuAgACAAEKAABBeAAAAAAAAA==.Tayebeh:BAAANQADCgYIFQAAAA==.',
Te='Tektoniik:BAAANQADCgYICQABNQAFFAQICgANAFAeAA==.',
Th='Thatguy:BAAANQAECgcIBgABNQAECgoKLQAWAAMjAA==.Thebrownbear:BAAANQAECggICQAAAA==.Theebucket:BAAANQAECgcIBwAAAA==.Theo:BAAANQAFFAEIAQABNQAECgoKOgAnAMEaAA==.Therese:BAAANQADCgUIBQAAAA==.Theresee:BAAANQADCggIEAAAAA==.Thorylianna:BAAANQADCgYIBgABNQAECgoKRAAMAGsaAA==.',
Ti='Tionie:BAABNQAECn8bAAIEAAkKyxCUagDuAQAEAAkKyxCUagDuAQAAAA==.',
To='Toiletnuker:BAAANQADCgUJCQABNQAECgoKMQABAIciAA==.Tokyojoe:BAACNQAFFH8PAAIeAAUK/w7xBQARAQAeAAUK/w7xBQARAQA1AAQKfzMAAx4ACgrUFf0eAFgCAB4ACgrUFf0eAFgCABEAAQrSB32HADAAAAAA.Torrick:BAABNQAECn8YAAQOAAkK8hnUDABhAgAOAAkK8hnUDABhAgABAAYKRxTjcQBfAQAFAAMKtRBPJAG0AAABNQAECgoKMAANALAPAA==.Totemtot:BAABNQAECn8nAAIkAAkKWwRCIAAiAQAkAAkKWwRCIAAiAQAAAA==.Toupee:BAAANQADCgQIBAAAAA==.',
Tr='Tradrivia:BAAANQADCgMIAwABNQAECgoKQQAIAN0lAA==.Traelindra:BAAANQADCggIFwAAAA==.Tryxtyflyx:BAAANQAECgEIAQAAAA==.',
Ty='Tydistus:BAAANQADCgMIAwAAAA==.Tygrala:BAAANQADCgYICQABNQAECgoKQAAOAK0ZAA==.',
Uf='Uffizzle:BAAANQAECggIDwAAAA==.',
Ul='Ulf:BAABNQAECn89AAITAAoKCSEtGAATAwATAAoKCSEtGAATAwAAAA==.',
Un='Unheardssk:BAAANQADCgQIBAABNQAECgUIDwAGAAAAAA==.Unholycow:BAAANQABCgYICAAAAA==.',
Va='Valquirie:BAABNQAECn9EAAIMAAoKaxqyIgCgAgAMAAoKaxqyIgCgAgAAAA==.Varlamor:BAABNQAECn8jAAMCAAkKhAg1OwBPAQACAAkKhAg1OwBPAQAgAAIK8ALXAwEoAAAAAA==.Varolokiir:BAAANQADCgEIAQABNQAFFAQICgANAFAeAA==.Vathraen:BAAANQADCgYICgAAAA==.',
Ve='Velanistra:BAABNQAECn8iAAIFAAoKSgjbvwBUAQAFAAoKSgjbvwBUAQAAAA==.Velanya:BAAANQADCgUIBQAAAA==.Velnia:BAAANQAECgIIBAAAAA==.Vervane:BAABNQAECn84AAIRAAoKsgy4MQCMAQARAAoKsgy4MQCMAQAAAA==.',
Vg='Vgerr:BAABNQAECn8rAAIFAAkKUAqe0QA1AQAFAAkKUAqe0QA1AQAAAA==.',
Vi='Vidarus:BAAANQADCggICAABNQAFFAUIEQAFALkcAA==.',
Vo='Vohu:BAABNQAECn88AAMEAAoK/hvTWAAYAgAEAAkKDR3TWAAYAgAYAAgKfRGyLAAGAQAAAA==.Voidpower:BAABNQAECn8bAAIeAAoKtAjZIwB+AQAeAAoKtAjZIwB+AQAAAA==.Vozzle:BAAANQADCgQICwAAAA==.',
['Và']='Vàlentine:BAAANQADCgQIBAAAAA==.',
Wa='Walane:BAAANQAECgQIBAAAAA==.Waterlily:BAAANQADCgMIAwAAAA==.',
Wi='Wiglet:BAAANQADCgYIBgAAAA==.Windeyaho:BAABNQAECn8lAAIIAAoK4CP3BQA0AwAIAAoK4CP3BQA0AwAAAA==.',
Xa='Xal:BAAANQAECgQICAABNQAECgoKQAAOAGwgAA==.Xapwv:BAAANQADCgQIBAAAAA==.',
Xe='Xent:BAAANQAECgcIDQAAAA==.',
Xt='Xten:BAABNQAECn8eAAIKAAYK6BMvOQAzAQAKAAYK6BMvOQAzAQAAAA==.',
Yo='Yoshinox:BAABNQAECn9VAAIEAAoK3SEjDAB8AwAEAAoK3SEjDAB8AwAAAA==.',
Za='Zalth:BAAANQADCgIIAgAAAA==.',
Ze='Zelliph:BAAANQAECgUIEQAAAA==.Zenagdrina:BAABNQAECn8tAAIEAAoKsAdojwCXAQAEAAoKsAdojwCXAQAAAA==.Zenobiå:BAABNQAECn9IAAIJAAoKzxHFOADxAQAJAAoKzxHFOADxAQAAAA==.Zeypher:BAAANQADCgcIGgAAAA==.',
Zh='Zhaann:BAABNQAECn8eAAMCAAYK8AamNQDmAAACAAYK8AamNQDmAAAgAAUKZg6M0wCsAAAAAA==.',
Zi='Zinarra:BAAANQADCgcIBwAAAA==.Ziron:BAAANQADCgIIAgABNQAECgUIDwAGAAAAAA==.Zironlock:BAABNQAECn8WAAILAAkK0RHjbAAXAgALAAkK0RHjbAAXAgABNQAECgUIDwAGAAAAAA==.',
Zo='Zorach:BAAANQAECgIIAgAAAA==.',
Zu='Zugga:BAAANQAECggIEgABNQAFFAUIDwAeAP8OAA==.',
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

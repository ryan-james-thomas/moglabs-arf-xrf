classdef mogchannel < handle
    properties(SetAccess = protected)
        parent
    end
    
    properties
        freq
        pow
        phase
        mode
        signal
        amplifier
    end
    
    properties(SetAccess = immutable)
        channel
    end
    
    properties(Constant)
        FREQ_BITS = 32;
        CLK = 1e3;  %In MHz, so 1 GHz
        MODE = 'NSB';
    end
    
    methods
        function self = mogchannel(parent,channel)
            if ~isa(parent,'mogdevice')
                error('Parent must be a ''mogdevice'' object!');
            end
            self.parent = parent;
            self.channel = channel;
        end
        
        function self = setDefaults(self)
            self.freq = 110;
            self.pow = 30;
            self.phase = 0;
            self.amplifier = 1;
            self.signal = 0;
        end
        
        function self = set(self,varargin)
            if mod(numel(varargin),2) ~= 0
                error('Arguments must be in name/value pairs!')
            else
                for nn = 1:2:numel(varargin)
                    v = varargin{nn+1};
                    switch lower(varargin{nn})
                        case 'freq'
                            self.freq = v;
                        case 'power'
                            self.pow = v;
                        case 'phase'
                            self.phase = v;
                        case 'signal'
                            self.signal = v;
                        case 'amplifier'
                            self.amplifier = v;
                        otherwise
                            error('Unknown property %s',varargin{nn});
                    end
                end
            end
        end
        
        function self = check(self)
            %Check frequency
            if self.freq > 400 || self.freq < 10
                error('Frequency %.6f MHz is out of range!',self.freq);
            end
            %Check power
            if self.pow > 35.1
                error('Power %.2f is out of range',self.pow);
            end
            %Wrap phase
            self.phase = mod(self.phase,360);            
        end
        
        function self = upload(self)
            self.check;
            self.parent.cmd('mode,%d,%s',self.channel,self.MODE);
            self.parent.cmd('freq,%d,%.6fMHz',self.channel,self.freq);
            self.parent.cmd('pow,%d,%.3fdBm',self.channel,self.pow);
            self.parent.cmd('phase,%d,%.6fdeg',self.channel,self.phase);
            self.parent.cmd('%s,%d,sig',onoff(self.signal),self.channel);
            self.parent.cmd('%s,%d,pow',onoff(self.amplifier),self.channel);
        end
        
        function self = write(self,varargin)
            self.set(varargin{:});
            self.upload;
        end
        
        function self = read(self)
            self.parent.cmd('mode,%d,%s',self.channel,self.MODE);
            self.readFreq;
            self.readPow;
            self.readPhase;
            self.readStatus;
        end

        function f = readFreq(self)
            r = self.parent.ask('freq,%d',self.channel);
            r = regexp(r,'(?<=0x)\w+','match');
            f = hex2dec(r)/2^self.FREQ_BITS*self.CLK;
            self.freq = f;
        end
        
        function r = readPow(self)
            r = self.parent.ask('pow,%d',self.channel);
            r = str2double(regexp(r,'^\d+\.\d+','match'));
            self.pow = r;
        end
        
%         function r = readMode(self)
%             r = self.parent.ask('mode,%d',self.channel);
%             r = regexp(r,'(?<=\()\w+','match');
%             self.mode = r{1};
%         end
        
        function r = readPhase(self)
            r = self.parent.ask('phase,%d',self.channel);
            r = str2double(regexp(r,'^\d+\.\d+','match'));
            self.phase = r;
        end
        
        function r = readStatus(self)
            r = self.parent.ask('status,%d',self.channel);
            rsig = regexp(r,'(?<=SIG: )\w+','match');
            self.signal = onoff(rsig{1});
            rpow = regexp(r,'(?<=POW: )\w+','match');
            self.amplifier = onoff(rpow{1});
        end

    end

end

function r = onoff(v)
    if isnumeric(v)
        if v
            r = 'on';
        else
            r = 'off';
        end
    elseif ischar(v)
        if strcmpi(v,'on')
            r = 1;
        elseif strcmpi(v,'off')
            r = 0;
        end
    end
end